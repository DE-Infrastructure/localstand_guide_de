FROM apache/airflow:2.8.4

USER airflow
RUN pip install --no-cache-dir "dbt-core" "dbt-postgres"