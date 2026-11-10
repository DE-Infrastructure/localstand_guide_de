"""Fast SQL/data checks using DuckDB, plus PostgreSQL syntax parsing.

This does NOT replace an end-to-end run against Greenplum and Airflow.
Run from the repository root: python tests/check_models.py
"""

import ast
import re
from decimal import Decimal
from pathlib import Path

import duckdb
import yaml
from jinja2 import Environment, StrictUndefined
from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
MODELS = {p.stem: p for p in (ROOT / "dbt_project/models").rglob("*.sql")}
ENV = Environment(undefined=StrictUndefined)
ENV.globals.update(
    config=lambda **kwargs: "",
    ref=lambda name: f"{MODELS[name].parent.name}.{name}",
    source=lambda source_name, table: f"raw.{table}",
)


def render(path):
    text = ENV.from_string(path.read_text()).render()
    parse_sql(text)
    return text


def load_raw(conn):
    for (table,) in conn.execute(
        "select table_name from information_schema.tables where table_schema = 'academy'"
    ).fetchall():
        conn.execute(f"create or replace table raw.{table} as select *, "
                     "'check' as _batch_id, current_timestamp as _loaded_at "
                     f"from academy.{table}")


def build(conn):
    pending = dict(MODELS)
    built = set()
    while pending:
        for name, path in list(pending.items()):
            refs = re.findall(r"ref\('([^']+)'\)", path.read_text())
            if set(refs) <= built:
                conn.execute(f"create or replace table {path.parent.name}.{name} as {render(path)}")
                built.add(name)
                del pending[name]
        if not pending:
            break
        if not any(set(re.findall(r"ref\('([^']+)'\)", p.read_text())) <= built for p in pending.values()):
            raise AssertionError(f"Unresolved model dependencies: {list(pending)}")


def check_tests(conn):
    for path in (ROOT / "dbt_project/tests").glob("*.sql"):
        assert conn.execute(render(path)).fetchall() == [], path.name
    model_schema = yaml.safe_load((ROOT / "dbt_project/models/schema.yml").read_text())
    for model in model_schema["models"]:
        relation = ENV.globals["ref"](model["name"])
        for column in model["columns"]:
            col = column["name"]
            for test in column["tests"]:
                if test == "unique":
                    query = f"select {col} from {relation} group by {col} having count(*) > 1"
                elif test == "not_null":
                    query = f"select * from {relation} where {col} is null"
                elif "relationships" in test:
                    target = test["relationships"]
                    parent = ENV.from_string("{{ " + target["to"] + " }}").render()
                    query = f"select * from {relation} c where not exists (select 1 from {parent} p where p.{target['field']} = c.{col})"
                else:
                    values = ", ".join(repr(v) for v in test["accepted_values"]["values"])
                    query = f"select * from {relation} where {col} not in ({values})"
                assert conn.execute(query).fetchall() == [], (relation, col, test)


def metrics(conn):
    return {
        "students": conn.execute("select count(*) from core.dim_students").fetchone()[0],
        "orders": conn.execute("select count(*) from core.fct_orders").fetchone()[0],
        "paid_orders": conn.execute("select count(*) from core.fct_orders where is_paid").fetchone()[0],
        "items": conn.execute("select count(*) from core.fct_order_items").fetchone()[0],
        "raw_enrollments": conn.execute("select count(*) from raw.enrollments").fetchone()[0],
        "raw_events": conn.execute("select count(*) from raw.lesson_events").fetchone()[0],
        "net_rub": Decimal(str(conn.execute("select sum(net_sales_rub) from marts.mart_sales_daily").fetchone()[0])),
    }


def main():
    for folder in ("airflow/dags", "scripts", "tests"):
        for path in (ROOT / folder).rglob("*.py"):
            ast.parse(path.read_text())
    for path in ROOT.rglob("*.yml"):
        yaml.safe_load(path.read_text())
    yaml.safe_load((ROOT / "docker-compose.yaml").read_text())
    conn = duckdb.connect()
    conn.create_function("initcap", lambda value: value.title(), ["VARCHAR"], "VARCHAR")
    for schema in ("raw", "staging", "core", "marts"):
        conn.execute(f"create schema {schema}")
    seed = (ROOT / "client-postgres-init/01_academy.sql").read_text().replace("\\set ON_ERROR_STOP on", "")
    parse_sql(seed)
    # COPY column lists must match both source and target contracts.
    import sys
    sys.path.insert(0, str(ROOT / "airflow/dags"))
    from dwh.contract import TABLES
    raw_ddl = (ROOT / "greenplum/01_raw.sql").read_text()
    parse_sql(re.sub(r"DISTRIBUTED BY \([^)]*\)", "", raw_ddl))
    for table, columns in TABLES.items():
        source_body = re.search(rf"CREATE TABLE academy\.{table} \((.*?)\n\);", seed, re.S)[1]
        raw_body = re.search(rf"CREATE TABLE IF NOT EXISTS raw\.{table} \((.*?)\n\)", raw_ddl, re.S)[1]
        pattern = r"^\s*(\w+) (?:integer|bigint|text|timestamptz)\b"
        assert tuple(re.findall(pattern, source_body, re.M)) == columns, table
        assert tuple(re.findall(pattern, raw_body, re.M)) == (*columns, "_batch_id", "_loaded_at"), table
    conn.execute(seed)
    load_raw(conn)
    build(conn)
    check_tests(conn)
    before = metrics(conn)
    assert (before["students"], before["orders"], before["paid_orders"], before["items"], before["raw_enrollments"]) == (200, 400, 320, 800, 640)
    assert before["raw_events"] == 4223, "Learning data must remain available for the exercises"
    # Independently reconcile mart money to source payments minus processed refunds.
    source_net = conn.execute("""
        select (select sum(amount_kopecks) from academy.payments where lower(trim(status)) = 'succeeded')
             - (select sum(amount_kopecks) from academy.refunds where lower(trim(status)) = 'processed')
    """).fetchone()[0]
    assert before["net_rub"] == Decimal(source_net) / 100
    load_raw(conn)
    build(conn)
    check_tests(conn)
    assert metrics(conn) == before, "Rerun must preserve business results"
    print("Baseline:", before)

    changes = (ROOT / "scripts/demo_changes.sql").read_text().replace("\\set ON_ERROR_STOP on", "")
    parse_sql(changes)
    conn.execute(changes)
    conn.execute(changes)
    load_raw(conn)
    build(conn)
    check_tests(conn)
    after = metrics(conn)
    assert after["orders"] == 401 and after["raw_enrollments"] == 642
    assert after["net_rub"] - before["net_rub"] == Decimal("27800")
    assert after["raw_events"] == before["raw_events"] + 2
    print("After demo changes applied twice:", after)

    # A partial payment must fail the financial check.
    conn.execute("update raw.payments set amount_kopecks = amount_kopecks / 2 where payment_id = 10011")
    build(conn)
    assert conn.execute(render(ROOT / "dbt_project/tests/payments_reconcile.sql")).fetchall()
    print(f"PASS: {len(MODELS)} models, schema checks, all singular tests, rerun, changes, negative payment case")


if __name__ == "__main__":
    main()
