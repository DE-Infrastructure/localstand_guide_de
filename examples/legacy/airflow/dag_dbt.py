from airflow.operators.bash import BashOperator
import pendulum

from airflow import DAG

with DAG(
    "dag_dbt",
    description="ETL DAG that extracts data from postgres",
    schedule_interval=None,
    start_date=pendulum.datetime(2021, 1, 1, tz="UTC"),
    catchup=False,
    tags=["piotrek"],
) as dag:
    dag.doc_md = __doc__

    dbt_debug = BashOperator(
        task_id="dbt_run",
        bash_command=(
            "cd /dbt && export DBT_PROFILES_DIR=/dbt && dbt debug --connection"
        ),
    )
