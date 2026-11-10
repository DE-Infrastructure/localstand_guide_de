"""Atomic full-snapshot loading for a small training dataset."""

import logging
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from tempfile import SpooledTemporaryFile

from psycopg2 import sql

from dwh.contract import TABLES

LOG = logging.getLogger(__name__)


def load_snapshot(source, warehouse, batch_id, ddl_path):
    """Caller owns connections. A failure rolls back every raw table and audit row.

    PostgreSQL REPEATABLE READ gives all eight tables one consistent source
    snapshot. COPY spools large extracts to a temporary file, outside XCom.
    """
    loaded_at = datetime.now(timezone.utc)
    source.set_session(isolation_level="REPEATABLE READ", readonly=True)
    counts = {}
    with source, warehouse:
        with source.cursor() as src, warehouse.cursor() as dst:
            src.execute("SET LOCAL TIME ZONE 'UTC'")
            dst.execute("SET LOCAL TIME ZONE 'UTC'")
            dst.execute("SET LOCAL statement_timeout = '300s'")
            dst.execute(Path(ddl_path).read_text())
            dst.execute("LOCK TABLE etl.pipeline_lock IN EXCLUSIVE MODE")
            dst.execute("DELETE FROM etl.load_audit WHERE batch_id = %s", (batch_id,))
            # Lock and replace all tables inside the same Greenplum transaction.
            dst.execute(sql.SQL("TRUNCATE {}").format(sql.SQL(", ").join(
                sql.Identifier("raw", name) for name in TABLES
            )))
            for name, columns in TABLES.items():
                names = sql.SQL(", ").join(map(sql.Identifier, columns))
                export = sql.SQL(
                    "COPY (SELECT {}, {}, {} FROM {}) TO STDOUT WITH CSV"
                ).format(names, sql.Literal(batch_id), sql.Literal(loaded_at),
                         sql.Identifier("academy", name))
                target_columns = sql.SQL(", ").join(map(
                    sql.Identifier, (*columns, "_batch_id", "_loaded_at")
                ))
                import_sql = sql.SQL("COPY {} ({}) FROM STDIN WITH CSV").format(
                    sql.Identifier("raw", name), target_columns
                )
                src.execute(sql.SQL("SELECT count(*) FROM {}").format(
                    sql.Identifier("academy", name)
                ))
                expected = src.fetchone()[0]
                if name in ("students", "courses", "orders") and expected == 0:
                    raise ValueError(f"Source {name} is unexpectedly empty")
                with SpooledTemporaryFile(max_size=8 * 1024 * 1024, mode="w+b") as data:
                    src.copy_expert(export.as_string(src), data)
                    data.seek(0)
                    dst.copy_expert(import_sql.as_string(dst), data)
                dst.execute(sql.SQL("SELECT count(*) FROM {}").format(
                    sql.Identifier("raw", name)
                ))
                actual = dst.fetchone()[0]
                if actual != expected:
                    raise ValueError(f"{name}: source={expected}, raw={actual}")
                dst.execute(
                    "INSERT INTO etl.load_audit VALUES (%s, %s, %s, %s)",
                    (batch_id, name, actual, loaded_at),
                )
                counts[name] = actual
                LOG.info("Copied %s: %s rows", name, actual)
    return counts


def load_from_airflow(**context):
    # Lazy import also lets integration tests exercise the loader without Airflow.
    from airflow.hooks.base import BaseHook
    import psycopg2

    def connect(conn_id):
        config = BaseHook.get_connection(conn_id)
        return psycopg2.connect(
            host=config.host, port=config.port or 5432, user=config.login,
            password=config.password, dbname=config.schema, connect_timeout=15,
        )

    with closing(connect("source_postgres")) as source, closing(connect("greenplum")) as warehouse:
        return load_snapshot(
            source, warehouse, context["run_id"], "/opt/airflow/greenplum/01_raw.sql"
        )
