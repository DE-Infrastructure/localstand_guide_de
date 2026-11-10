-- PostgreSQL source values are copied unchanged; ingestion metadata is added.

CREATE SCHEMA IF NOT EXISTS raw;

CREATE SCHEMA IF NOT EXISTS staging;

CREATE SCHEMA IF NOT EXISTS core;

CREATE SCHEMA IF NOT EXISTS marts;

CREATE SCHEMA IF NOT EXISTS etl;

CREATE TABLE IF NOT EXISTS etl.pipeline_lock (id integer) DISTRIBUTED BY (id);

CREATE TABLE IF NOT EXISTS etl.load_audit (

    batch_id text, table_name text, row_count bigint, loaded_at timestamptz

) DISTRIBUTED BY (batch_id);

CREATE TABLE IF NOT EXISTS raw.students (
    student_id integer,
    full_name text,
    email text,
    city text,
    acquired_via text,
    registered_at timestamptz,
    updated_at timestamptz,
    _batch_id text NOT NULL,
    _loaded_at timestamptz NOT NULL
) DISTRIBUTED BY (student_id);

CREATE TABLE IF NOT EXISTS raw.courses (
    course_id integer,
    title text,
    category text,
    price_kopecks bigint,
    total_lessons integer,
    updated_at timestamptz,
    _batch_id text NOT NULL,
    _loaded_at timestamptz NOT NULL
) DISTRIBUTED BY (course_id);

CREATE TABLE IF NOT EXISTS raw.orders (
    order_id integer,
    student_id integer,
    ordered_at timestamptz,
    status text,
    updated_at timestamptz,
    _batch_id text NOT NULL,
    _loaded_at timestamptz NOT NULL
) DISTRIBUTED BY (order_id);

CREATE TABLE IF NOT EXISTS raw.order_items (
    order_item_id integer,
    order_id integer,
    course_id integer,
    price_kopecks bigint,
    discount_kopecks bigint,
    updated_at timestamptz,
    _batch_id text NOT NULL,
    _loaded_at timestamptz NOT NULL
) DISTRIBUTED BY (order_item_id);

CREATE TABLE IF NOT EXISTS raw.payments (
    payment_id integer,
    order_id integer,
    amount_kopecks bigint,
    status text,
    paid_at timestamptz,
    updated_at timestamptz,
    _batch_id text NOT NULL,
    _loaded_at timestamptz NOT NULL
) DISTRIBUTED BY (payment_id);

CREATE TABLE IF NOT EXISTS raw.refunds (
    refund_id integer,
    order_item_id integer,
    amount_kopecks bigint,
    status text,
    refunded_at timestamptz,
    updated_at timestamptz,
    _batch_id text NOT NULL,
    _loaded_at timestamptz NOT NULL
) DISTRIBUTED BY (refund_id);

CREATE TABLE IF NOT EXISTS raw.enrollments (
    enrollment_id integer,
    order_item_id integer,
    enrolled_at timestamptz,
    updated_at timestamptz,
    _batch_id text NOT NULL,
    _loaded_at timestamptz NOT NULL
) DISTRIBUTED BY (enrollment_id);

CREATE TABLE IF NOT EXISTS raw.lesson_events (
    delivery_id bigint,
    event_id bigint,
    enrollment_id integer,
    lesson_no integer,
    event_type text,
    event_at timestamptz,
    received_at timestamptz,
    _batch_id text NOT NULL,
    _loaded_at timestamptz NOT NULL
) DISTRIBUTED BY (delivery_id);
