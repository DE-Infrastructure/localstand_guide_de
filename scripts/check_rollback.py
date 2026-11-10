"""Integration check: interrupt COPY after several tables, verify full rollback.

Run after smoke_test.py, while no other DAG run is active.
"""

import os
import sys
from contextlib import closing
from uuid import uuid4

import psycopg2

sys.path.insert(0, "/opt/airflow/dags")
from dwh.contract import TABLES
from dwh.load import load_snapshot


class InjectedFailure(RuntimeError):
    pass


class FailingCursor(psycopg2.extensions.cursor):
    def copy_expert(self, statement, file):
        if '"raw"."refunds"' in statement:
            raise InjectedFailure("Simulated COPY failure after five tables")
        return super().copy_expert(statement, file)


def snapshot(connection):
    with connection, connection.cursor() as cursor:
        values = {}
        for table, columns in TABLES.items():
            cursor.execute(f"select * from raw.{table} order by {columns[0]}")
            values[table] = cursor.fetchall()
        cursor.execute("select * from etl.load_audit order by batch_id, table_name")
        values["audit"] = cursor.fetchall()
        return values


if __name__ == "__main__":
    with closing(psycopg2.connect(os.environ["AIRFLOW_CONN_SOURCE_POSTGRES"])) as source, \
         closing(psycopg2.connect(os.environ["AIRFLOW_CONN_GREENPLUM"], cursor_factory=FailingCursor)) as warehouse:
        before = snapshot(warehouse)
        try:
            load_snapshot(source, warehouse, "rollback_" + uuid4().hex,
                          "/opt/airflow/greenplum/01_raw.sql")
        except InjectedFailure:
            pass
        else:
            raise RuntimeError("Failure injection did not happen")
        if snapshot(warehouse) != before:
            raise RuntimeError("Partial data became visible after a failed load")
        print("PASS: raw data, ingestion metadata and audit survived a failed COPY unchanged")
