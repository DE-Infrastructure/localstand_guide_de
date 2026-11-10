"""Postgres → Greenplum raw → dbt staging → core → marts.

The supplied example builds mart_sales_daily. Other marts are student exercises.
The dwh Compose profile enables the first automatic run after both databases are
ready. The base Airflow/dbt mode leaves this DAG paused. Trigger another run after
scripts/demo_changes.sql.
"""

from datetime import timedelta

import pendulum
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

from dwh.load import load_from_airflow

with DAG(
    dag_id="academy_dwh",
    description="Учебное DWH онлайн-школы: источник, загрузка, очистка, факты, витрины",
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    schedule="@once",
    catchup=False,
    is_paused_upon_creation=True,
    max_active_runs=1,
    default_args={"owner": "de-guide", "retries": 1, "retry_delay": timedelta(seconds=30)},
    dagrun_timeout=timedelta(minutes=30),
    tags=["dwh", "greenplum", "dbt", "academy"],
) as dag:
    dag.doc_md = __doc__
    load_raw = PythonOperator(
        task_id="load_raw", python_callable=load_from_airflow,
        execution_timeout=timedelta(minutes=10),
    )

    def build_layer(layer):
        return BashOperator(
            task_id=f"dbt_{layer}",
            bash_command=(
                "/opt/dbt-venv/bin/dbt build --project-dir /dbt --profiles-dir /dbt "
                f"--select path:models/{layer} --indirect-selection cautious"
            ),
            execution_timeout=timedelta(minutes=10),
        )

    staging = build_layer("staging")
    core = build_layer("core")
    marts = build_layer("marts")
    tests = BashOperator(
        task_id="dbt_test_all",
        bash_command="/opt/dbt-venv/bin/dbt test --project-dir /dbt --profiles-dir /dbt",
        execution_timeout=timedelta(minutes=10),
    )
    verify = BashOperator(
        task_id="verify_marts",
        bash_command="python /opt/airflow/scripts/verify_warehouse.py",
    )
    load_raw >> staging >> core >> marts >> tests >> verify
