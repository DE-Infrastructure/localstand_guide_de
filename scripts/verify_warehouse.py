"""Check a real Greenplum deployment. Run inside the Airflow container."""

import argparse
import json
import os
from contextlib import closing
from decimal import Decimal

import psycopg2

BASELINE = {
    "students": 200, "courses": 6, "orders": 400, "paid_orders": 320,
    "items": 800, "raw_enrollments": 640, "raw_events": 4223,
    "net_rub": Decimal("7158110.00"),
}
CHANGED = dict(BASELINE, orders=401, paid_orders=321, items=802,
               raw_enrollments=642, raw_events=4225,
               net_rub=Decimal("7185910.00"))
RAW_TABLES = ("students", "courses", "orders", "order_items", "payments",
              "refunds", "enrollments", "lesson_events")


def connect():
    return psycopg2.connect(
        host=os.getenv("GP_HOST", "greenplum"), port=os.getenv("GP_PORT", "5432"),
        user=os.getenv("GP_USER", "gpadmin"), password=os.getenv("GP_PASSWORD", "gpadmin"),
        dbname=os.getenv("GP_DATABASE", "dwh"), connect_timeout=15,
    )


def verify(expected=None):
    with closing(connect()) as conn, conn, conn.cursor() as cur:
        cur.execute("select version()")
        if "Greenplum" not in cur.fetchone()[0]:
            raise RuntimeError("Expected a real Greenplum database")
        cur.execute("select content, status from gp_segment_configuration "
                    "where content >= 0 and role = 'p'")
        segments = cur.fetchall()
        if len(segments) < 2 or any(status != "u" for _, status in segments):
            raise RuntimeError(f"Expected at least two healthy primary segments: {segments}")
        cur.execute("select gp_segment_id, count(*) from core.fct_order_items "
                    "group by gp_segment_id order by gp_segment_id")
        distribution = cur.fetchall()
        if len(distribution) < 2:
            raise RuntimeError(f"Order items are not distributed across segments: {distribution}")
        print(f"MPP: {len(segments)} primary segments up; order items by segment: {distribution}")
        metrics = {}
        for name, query in {
            "students": "select count(*) from core.dim_students",
            "courses": "select count(*) from core.dim_courses",
            "orders": "select count(*) from core.fct_orders",
            "paid_orders": "select count(*) from core.fct_orders where is_paid",
            "items": "select count(*) from core.fct_order_items",
            "raw_enrollments": "select count(*) from raw.enrollments",
            "raw_events": "select count(*) from raw.lesson_events",
            "net_rub": "select sum(net_sales_rub) from marts.mart_sales_daily",
        }.items():
            cur.execute(query)
            metrics[name] = cur.fetchone()[0]
        for query in (
            "select sum(net_kopecks) / 100.0 from core.fct_orders",
            """select (
                (select sum(amount_kopecks) from raw.payments where lower(trim(status)) = 'succeeded')
                - (select coalesce(sum(amount_kopecks), 0) from raw.refunds where lower(trim(status)) = 'processed')
            ) / 100.0""",
        ):
            cur.execute(query)
            if cur.fetchone()[0] != metrics["net_rub"]:
                raise RuntimeError(f"Sales do not reconcile: {query}")
        cur.execute("select distinct _batch_id from raw.orders")
        batches = cur.fetchall()
        if len(batches) != 1:
            raise RuntimeError("Expected one current raw batch")
        batch_id = batches[0][0]
        for table in RAW_TABLES:
            cur.execute(f"select count(*) from raw.{table}")
            row_count = cur.fetchone()[0]
            cur.execute(f"select count(*) from raw.{table} where _batch_id <> %s", (batch_id,))
            if cur.fetchone()[0] != 0:
                raise RuntimeError(f"Mixed snapshots in raw.{table}")
            cur.execute("select row_count from etl.load_audit where batch_id = %s and table_name = %s",
                        (batch_id, table))
            if cur.fetchall() != [(row_count,)]:
                raise RuntimeError(f"Audit mismatch for raw.{table}")
        if expected:
            wanted = {"baseline": BASELINE, "changed": CHANGED}[expected]
            if metrics != wanted:
                raise RuntimeError(f"Expected {wanted}; got {metrics}")
        print(json.dumps(metrics, ensure_ascii=False, default=str, indent=2))
        return metrics


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected", choices=["baseline", "changed"])
    verify(parser.parse_args().expected)
