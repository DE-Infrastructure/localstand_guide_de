FROM apache/airflow:2.10.5-python3.10@sha256:04dfd8de3539a1265eb4ca4446982670ea0274cadf60d1edef2e62263c7b9ba0

# dbt-greenplum uses dbt 1.5. Keep its dependencies outside Airflow's environment.
USER root
RUN mkdir /opt/dbt-venv && chown airflow:0 /opt/dbt-venv
USER airflow
COPY requirements-dbt.txt constraints-dbt.txt /tmp/
RUN python -m venv /opt/dbt-venv \
    && PIP_USER=false /opt/dbt-venv/bin/pip install --no-cache-dir -r /tmp/requirements-dbt.txt -c /tmp/constraints-dbt.txt \
    && /opt/dbt-venv/bin/pip check \
    && /opt/dbt-venv/bin/dbt --version

ENV DBT_PROFILES_DIR=/dbt \
    DBT_SEND_ANONYMOUS_USAGE_STATS=false \
    DBT_TARGET_PATH=/opt/airflow/logs/dbt/target \
    DBT_LOG_PATH=/opt/airflow/logs/dbt
