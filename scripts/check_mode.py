"""Check the Airflow/dbt or source-only mode without connecting to Greenplum."""

import argparse
import json
import os
import time
import urllib.error
import urllib.request

import psycopg2

from smoke_test import api


def check(mode, allow_existing_runs=False):
    deadline = time.monotonic() + 300
    while True:
        try:
            info = api()
            break
        except urllib.error.HTTPError as error:
            if error.code not in (404, 502, 503, 504):
                raise
        except (urllib.error.URLError, TimeoutError):
            pass
        if time.monotonic() >= deadline:
            raise TimeoutError("Airflow API or warehouse DAG was not ready within five minutes")
        time.sleep(2)
    if not info["is_paused"]:
        raise RuntimeError("Warehouse DAG must remain paused until the dwh profile is enabled")
    runs = api("/dagRuns?limit=1")
    if not allow_existing_runs and runs["total_entries"] != 0:
        raise RuntimeError(f"Expected no warehouse DAG runs in fresh {mode} mode: {runs}")
    with urllib.request.urlopen("http://airflow-webserver:8080/health", timeout=20) as response:
        health = json.load(response)
    for component in ("metadatabase", "scheduler"):
        if health[component]["status"] != "healthy":
            raise RuntimeError(f"Airflow {component} is not healthy: {health}")
    if mode == "source":
        conn = psycopg2.connect(os.environ["AIRFLOW_CONN_SOURCE_POSTGRES"], connect_timeout=15)
        try:
            with conn, conn.cursor() as cursor:
                cursor.execute("select count(*) from academy.orders")
                count = cursor.fetchone()[0]
                if count != 400:
                    raise RuntimeError(f"Expected the initial source dataset: 400 orders, got {count}")
        finally:
            conn.close()
    print(f"PASS: {mode} mode; Airflow healthy, warehouse DAG paused"
          + (", existing run history preserved" if allow_existing_runs else ", no warehouse DAG runs"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("base", "source"), default="base")
    parser.add_argument("--allow-existing-runs", action="store_true",
                        help="Allow successful runs retained when returning from dwh mode")
    args = parser.parse_args()
    check(args.mode, args.allow_existing_runs)
