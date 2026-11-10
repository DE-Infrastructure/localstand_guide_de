"""Enable the warehouse DAG after the dwh profile's databases become healthy.

Use the metadata DB because the webserver waits for this one-shot to complete.
Unpausing an existing DAG preserves its run history and does not repeat @once.
"""

import time

from airflow.models.dag import DagModel
from airflow.utils.session import create_session

DAG_ID = "academy_dwh"


def enable():
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        with create_session() as session:
            model = session.query(DagModel).filter(DagModel.dag_id == DAG_ID).one_or_none()
            if model is not None and model.is_active:
                was_paused = model.is_paused
                model.is_paused = False
                session.commit()
                print(f"PASS: {DAG_ID} enabled; was_paused={was_paused}", flush=True)
                return
        print(f"Waiting for scheduler to register {DAG_ID}", flush=True)
        time.sleep(2)
    raise TimeoutError(f"Scheduler did not register {DAG_ID} within five minutes")


if __name__ == "__main__":
    enable()
