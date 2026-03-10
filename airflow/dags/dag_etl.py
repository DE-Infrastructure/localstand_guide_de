from datetime import datetime, timedelta
import logging
import requests
import pendulum

from airflow import DAG
from airflow.operators.python_operator import PythonOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from psycopg2.extras import execute_values


BASE_URL = "https://jsonplaceholder.typicode.com"

CREATE_TABLE = """
    CREATE TABLE IF NOT EXISTS public.users (
        id        integer PRIMARY KEY,
        name      text,
        username  text,
        email     text,
        phone     text,
        website   text,
        loaded_at timestamptz NOT NULL DEFAULT now()
    );
"""

INSERT = """
    INSERT INTO public.users
        (id, name, username, email, phone, website)
    VALUES %s
    ON CONFLICT (id) DO UPDATE SET
        name      = EXCLUDED.name,
        username  = EXCLUDED.username,
        email     = EXCLUDED.email,
        phone     = EXCLUDED.phone,
        website   = EXCLUDED.website,
        loaded_at = now();
"""


def fetch(endpoint, params=None):
    url = "{}/{}".format(BASE_URL, endpoint)
    r = requests.get(url, params=params, timeout=30)
    r.raise_for_status()
    return r.json()


default_args = {
    "owner": "iblabla",
    "depends_on_past": False,
    "start_date": pendulum.datetime(2021, 1, 1, tz="UTC"),
    "retries": 1,
}

dag = DAG(
    dag_id="dag_etl",
    default_args=default_args,
    schedule_interval=None,
    catchup=False,
    tags=["demo", "api", "jsonplaceholder"],
)

log = logging.getLogger("airflow.task")


def get_users(**context):
    users = fetch("users")
    log.info("users: %s first: %s", len(users), users[0] if users else None)
    # вернём список — он уедет в XCom
    return users


def create_users_table(**context):
    PostgresHook(postgres_conn_id="client-postgres").run(CREATE_TABLE)
    log.info("Ensured schema/table public.users")


def load_users(**context):
    ti = context["ti"]
    users = ti.xcom_pull(task_ids="get_users")
    if not users:
        log.info("No users to load")
        return

    rows = [
        (
            u["id"],
            u.get("name"),
            u.get("username"),
            u.get("email"),
            u.get("phone"),
            u.get("website"),
        )
        for u in users
    ]

    hook = PostgresHook(postgres_conn_id="client-postgres")
    conn = hook.get_conn()
    cur = conn.cursor()

    execute_values(cur, INSERT, rows, page_size=1000)
    conn.commit()
    cur.close()
    conn.close()

    log.info("Upserted %s users into public.users", len(rows))


t_create_users_table = PythonOperator(
    task_id="create_users_table",
    python_callable=create_users_table,
    provide_context=True,
    dag=dag,
)

t_get_users = PythonOperator(
    task_id="get_users",
    python_callable=get_users,
    provide_context=True,
    dag=dag,
)

t_load_users = PythonOperator(
    task_id="load_users",
    python_callable=load_users,
    provide_context=True,
    dag=dag,
)

[t_create_users_table, t_get_users] >> t_load_users
