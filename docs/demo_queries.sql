-- Run against Greenplum dwh after a successful academy_dwh DAG.
-- Only the supplied sales example is required; exercise models are optional.
\pset pager off

-- 1. Dirty source values and their cleaned equivalents.
SELECT r.student_id, r.email AS raw_email, s.email AS clean_email,
       r.city AS raw_city, s.city AS clean_city
FROM raw.students r
JOIN staging.stg_students s USING (student_id)
WHERE r.student_id <= 14
ORDER BY r.student_id;

-- 2. Data for the learning exercise is already in raw.
SELECT (SELECT count(*) FROM raw.enrollments) AS enrollments,
       (SELECT count(*) FROM raw.lesson_events) AS event_deliveries;

-- 3. One audit row per source table in each successful load.
SELECT batch_id, table_name, row_count, loaded_at
FROM etl.load_audit
ORDER BY loaded_at DESC, table_name
LIMIT 16;

-- 4. The supplied mart: UTC order date × course.
SELECT * FROM marts.mart_sales_daily
ORDER BY order_date DESC, course_id
LIMIT 20;

-- 5. Same money at order and mart grain.
SELECT (SELECT sum(gross_kopecks) / 100.0 FROM core.fct_orders) AS gross_sales_rub,
       (SELECT sum(refunded_kopecks) / 100.0 FROM core.fct_orders) AS refunds_rub,
       (SELECT sum(net_kopecks) / 100.0 FROM core.fct_orders) AS order_total,
       (SELECT sum(net_sales_rub) FROM marts.mart_sales_daily) AS daily_total;

-- 6. Data is distributed between Greenplum segments.
-- content=-1 is the coordinator; content=0 and 1 are primary segments.
SELECT dbid, content, role, status, hostname, port
FROM gp_segment_configuration ORDER BY content;

SELECT gp_segment_id, count(*) FROM core.fct_order_items
GROUP BY gp_segment_id ORDER BY gp_segment_id;

-- Grouping by a different key requires Redistribute Motion 2:2,
-- then Gather Motion 2:1 sends the result to the coordinator.
EXPLAIN SELECT course_id, sum(net_kopecks)
FROM core.fct_order_items GROUP BY course_id;

-- 7. After demo_changes.sql and another DAG run: 27,800 RUB and a new city.
SELECT * FROM core.fct_orders WHERE order_id = 1001;
SELECT student_id, city FROM core.dim_students WHERE student_id = 1;
SELECT * FROM marts.mart_sales_daily WHERE order_date = DATE '2026-04-16';
