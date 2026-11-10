"""Check automatic startup, then repeat the actual pipeline and compare results."""

import argparse
import base64
import json
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

from verify_warehouse import verify

BASE = "http://airflow-webserver:8080/api/v1/dags/academy_dwh"
AUTH = "Basic " + base64.b64encode(b"airflow:airflow").decode()


def api(path="", data=None):
    request = urllib.request.Request(
        BASE + path, data=json.dumps(data).encode() if data is not None else None,
        headers={"Authorization": AUTH, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def wait_for_dag():
    deadline = time.monotonic() + 900
    while time.monotonic() < deadline:
        try:
            info = api()
            if info["is_paused"]:
                raise RuntimeError("academy_dwh is paused; enable the dwh Compose profile "
                                   "before checking the warehouse")
            return
        except urllib.error.HTTPError as error:
            if error.code not in (404, 502, 503, 504):
                raise
        except (urllib.error.URLError, TimeoutError):
            # compose up -d may return before the webserver starts listening.
            pass
        time.sleep(5)
    raise TimeoutError("Airflow API or academy_dwh did not become ready within 15 minutes")


def wait_for_run(run_id):
    deadline = time.monotonic() + 900
    print(f"Waiting for {run_id}", flush=True)
    while time.monotonic() < deadline:
        state = api("/dagRuns/" + urllib.parse.quote(run_id, safe=""))["state"]
        if state == "success":
            print(f"PASS: {run_id}", flush=True)
            return
        if state == "failed":
            tasks = api("/dagRuns/" + urllib.parse.quote(run_id, safe="") + "/taskInstances")
            states = {task["task_id"]: task["state"] for task in tasks["task_instances"]}
            raise RuntimeError(f"DAG failed: {run_id}; tasks: {states}; inspect logs in Airflow")
        time.sleep(5)
    raise TimeoutError(f"DAG did not finish within 15 minutes: {run_id}")


def wait_for_initial_run():
    deadline = time.monotonic() + 900
    while time.monotonic() < deadline:
        runs = api("/dagRuns?limit=100&order_by=execution_date")["dag_runs"]
        for run in runs:
            if run["run_type"] == "scheduled":
                wait_for_run(run["dag_run_id"])
                return
        time.sleep(5)
    raise TimeoutError("Airflow did not create the automatic @once run")


def run_and_wait():
    run_id = "smoke_" + uuid.uuid4().hex
    api("/dagRuns", {"dag_run_id": run_id})
    wait_for_run(run_id)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected", choices=["baseline", "changed"], default="baseline")
    parser.add_argument("--initial-only", action="store_true",
                        help="Wait for the automatic first run and verify it without triggering a run")
    args = parser.parse_args()
    wait_for_dag()
    wait_for_initial_run()
    if args.initial_only:
        verify(args.expected)
        raise SystemExit(0)
    run_and_wait()
    first = verify(args.expected)
    run_and_wait()
    second = verify(args.expected)
    if first != second:
        raise RuntimeError("Repeated load changed business results")
    print("PASS: two successful DAG runs, stable row counts and reconciled money")
