-- Greenplum: database dwh. Select a numbered block in DBeaver,
-- or run everything with: bash scripts/gp_sql.sh < docs/video_warehouse_queries.sql
-- All queries are read-only. Baseline examples assume a successful initial DAG.
SET TIME ZONE 'UTC';

-- GP01. A real coordinator and two primary segments.
SELECT version();
SELECT dbid, content, role, status, hostname, port
FROM gp_segment_configuration ORDER BY content;

-- GP02. Physical data distribution, not just two process names.
SELECT gp_segment_id, count(*) AS order_items
FROM core.fct_order_items GROUP BY gp_segment_id ORDER BY gp_segment_id;
SELECT gp_segment_id, count(*) AS deliveries
FROM raw.lesson_events GROUP BY gp_segment_id ORDER BY gp_segment_id;

-- GP03. Distribution keys. An order item key differs from its distribution key.
SELECT 'core.fct_order_items' AS relation,
       pg_get_table_distributedby('core.fct_order_items'::regclass) AS distribution
UNION ALL
SELECT 'core.fct_orders', pg_get_table_distributedby('core.fct_orders'::regclass)
UNION ALL
SELECT 'marts.mart_sales_daily', pg_get_table_distributedby('marts.mart_sales_daily'::regclass);

-- GP04. Redistribute Motion 2:2, Gather Motion 2:1, GPORCA.
EXPLAIN SELECT course_id, sum(net_kopecks)
FROM core.fct_order_items GROUP BY course_id;

-- GP05. Raw preserves the source order and adds ingestion metadata.
SELECT order_id, student_id, ordered_at, quote_literal(status) AS status,
       updated_at, _batch_id, _loaded_at
FROM raw.orders WHERE order_id = 308;
SELECT payment_id, quote_literal(status) AS status, amount_kopecks
FROM raw.payments WHERE order_id = 308 ORDER BY payment_id;

-- GP06. Source time, business time, ingestion time: separate meanings.
SELECT order_id, ordered_at, updated_at, _loaded_at FROM raw.orders WHERE order_id = 308;

-- GP07. Same students, raw strings and cleaned strings side by side.
SELECT r.student_id, quote_literal(r.email) AS raw_email, s.email AS clean_email,
       quote_nullable(r.city) AS raw_city, s.city AS clean_city,
       quote_literal(r.acquired_via) AS raw_channel, s.acquired_via AS clean_channel
FROM raw.students r JOIN staging.stg_students s USING (student_id)
WHERE r.student_id BETWEEN 3 AND 7 ORDER BY r.student_id;
SELECT r.order_id, quote_literal(r.status) AS raw_status, s.status AS clean_status
FROM raw.orders r JOIN staging.stg_orders s USING (order_id) WHERE r.order_id = 308;

-- GP08. Result of the core rules for each item of order 308.
SELECT order_item_id, order_id, course_id, order_date, is_paid,
       (ordered_kopecks / 100.0)::numeric(12,2) AS ordered_rub,
       (gross_kopecks / 100.0)::numeric(12,2) AS gross_rub,
       (refunded_kopecks / 100.0)::numeric(12,2) AS refunded_rub,
       (net_kopecks / 100.0)::numeric(12,2) AS net_rub
FROM core.fct_order_items WHERE order_id = 308 ORDER BY order_item_id;

-- GP09. Deliberately WRONG calculation: show why row grain matters.
-- Two items x two payment attempts = four joined rows.
SELECT i.order_item_id, p.payment_id, p.status,
       (p.amount_kopecks / 100.0)::numeric(12,2) AS payment_rub
FROM staging.stg_order_items i
JOIN staging.stg_payments p ON p.order_id = i.order_id
WHERE i.order_id = 308 ORDER BY i.order_item_id, p.payment_id;
-- Even after filtering successful payments, summing order-level money per item doubles it.
SELECT count(*) AS joined_rows,
       (sum(p.amount_kopecks) / 100.0)::numeric(12,2) AS wrong_payment_sum_rub
FROM staging.stg_order_items i
JOIN staging.stg_payments p ON p.order_id = i.order_id
WHERE i.order_id = 308 AND p.status = 'succeeded';

-- GP10. One order per row. Pending and cancelled orders have zero sales.
SELECT order_id, order_status, item_count, is_paid,
       (ordered_kopecks / 100.0)::numeric(12,2) AS ordered_rub,
       (gross_kopecks / 100.0)::numeric(12,2) AS gross_rub,
       (refunded_kopecks / 100.0)::numeric(12,2) AS refunded_rub,
       (net_kopecks / 100.0)::numeric(12,2) AS net_rub
FROM core.fct_orders WHERE order_id IN (308, 310, 311) ORDER BY order_id;

-- GP11. Contributions from five orders to the same date and two courses.
SELECT order_id, course_id,
       (gross_kopecks / 100.0)::numeric(12,2) AS gross_rub,
       (refunded_kopecks / 100.0)::numeric(12,2) AS refunded_rub,
       (net_kopecks / 100.0)::numeric(12,2) AS net_rub
FROM core.fct_order_items WHERE order_date = DATE '2026-02-14'
ORDER BY order_id, course_id;

-- GP12. The final daily mart: two rows for February 14.
SELECT order_date, course_id, course_title, paid_orders, sold_items,
       gross_sales_rub::numeric(12,2), refunds_rub::numeric(12,2), net_sales_rub::numeric(12,2)
FROM marts.mart_sales_daily WHERE order_date = DATE '2026-02-14' ORDER BY course_id;

-- GP13. Reconciliation and an example of a non-additive order count.
SELECT count(*) AS mart_rows, sum(paid_orders) AS sum_orders_across_courses,
       sum(sold_items) AS sold_items, sum(net_sales_rub)::numeric(12,2) AS net_rub
FROM marts.mart_sales_daily;
SELECT count(*) AS unique_paid_orders FROM core.fct_orders WHERE is_paid;
SELECT
    ((SELECT sum(amount_kopecks) FROM raw.payments WHERE lower(trim(status)) = 'succeeded') / 100.0)::numeric(12,2) AS paid_rub,
    ((SELECT sum(amount_kopecks) FROM raw.refunds WHERE lower(trim(status)) = 'processed') / 100.0)::numeric(12,2) AS refunded_rub,
    ((SELECT sum(net_kopecks) FROM core.fct_orders) / 100.0)::numeric(12,2) AS core_net_rub,
    (SELECT sum(net_sales_rub) FROM marts.mart_sales_daily)::numeric(12,2) AS mart_net_rub;

-- GP14. Every successful raw load has eight audit rows; raw keeps only the last batch.
SELECT batch_id, count(*) AS tables_loaded, sum(row_count) AS rows_loaded, max(loaded_at) AS loaded_at
FROM etl.load_audit GROUP BY batch_id ORDER BY loaded_at DESC;
SELECT _batch_id, count(*) AS orders FROM raw.orders GROUP BY _batch_id;

-- GP15. SCD Type 1: one current city, no old versions of the student.
SELECT student_id, city, updated_at FROM raw.students WHERE student_id = 1;
SELECT student_id, city, updated_at FROM core.dim_students WHERE student_id = 1;

-- GP16. Empty initially. Run again after demo_changes.sql and the next DAG.
SELECT order_id, order_date, item_count, is_paid,
       (net_kopecks / 100.0)::numeric(12,2) AS net_rub
FROM core.fct_orders WHERE order_id = 1001;
SELECT order_date, course_id, course_title, paid_orders, sold_items,
       net_sales_rub::numeric(12,2) AS net_rub
FROM marts.mart_sales_daily WHERE order_date = DATE '2026-04-16' ORDER BY course_id;
