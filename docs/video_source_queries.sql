-- PostgreSQL source: database postgres, schema academy.
-- Run the selected block in DBeaver, or all blocks through psql:
-- docker compose exec -T client-postgres psql -U postgres -d postgres -v ON_ERROR_STOP=1 < docs/video_source_queries.sql
-- Read-only demonstration. Apply demo_changes.sql separately when the script says so.
SET TIME ZONE 'UTC';

-- PG01. Eight source tables: what one row means is explained in VIDEO_SCRIPT.md.
SELECT 'students' AS table_name, count(*) AS row_count FROM academy.students
UNION ALL SELECT 'courses', count(*) FROM academy.courses
UNION ALL SELECT 'orders', count(*) FROM academy.orders
UNION ALL SELECT 'order_items', count(*) FROM academy.order_items
UNION ALL SELECT 'payments', count(*) FROM academy.payments
UNION ALL SELECT 'refunds', count(*) FROM academy.refunds
UNION ALL SELECT 'enrollments', count(*) FROM academy.enrollments
UNION ALL SELECT 'lesson_events', count(*) FROM academy.lesson_events;

-- PG02. The catalog. Monetary amounts are stored in integer kopecks.
SELECT course_id, title, price_kopecks,
       (price_kopecks / 100.0)::numeric(12,2) AS price_rub, total_lessons
FROM academy.courses ORDER BY course_id;

-- PG03. Follow one real order through the whole pipeline.
SELECT o.order_id, o.student_id, s.full_name, o.ordered_at,
       quote_literal(o.status) AS source_status
FROM academy.orders o
JOIN academy.students s ON s.student_id = o.student_id
WHERE o.order_id = 308;

-- PG04. Two order items, each with a 10% discount.
SELECT i.order_item_id, i.order_id, i.course_id, c.title,
       (i.price_kopecks / 100.0)::numeric(12,2) AS list_price_rub,
       (i.discount_kopecks / 100.0)::numeric(12,2) AS discount_rub,
       ((i.price_kopecks - i.discount_kopecks) / 100.0)::numeric(12,2) AS due_rub
FROM academy.order_items i
JOIN academy.courses c ON c.course_id = i.course_id
WHERE i.order_id = 308 ORDER BY i.order_item_id;

-- PG05. A failed attempt and a successful payment are different rows.
SELECT payment_id, order_id, quote_literal(status) AS source_status,
       (amount_kopecks / 100.0)::numeric(12,2) AS amount_rub, paid_at
FROM academy.payments WHERE order_id = 308 ORDER BY payment_id;

-- PG06. A processed refund belongs to a specific item.
SELECT r.refund_id, r.order_item_id, quote_literal(r.status) AS source_status,
       (r.amount_kopecks / 100.0)::numeric(12,2) AS refund_rub, r.refunded_at
FROM academy.refunds r
JOIN academy.order_items i ON i.order_item_id = r.order_item_id
WHERE i.order_id = 308 ORDER BY r.refund_id;

-- PG07. Deliberately dirty strings. Quotes make spaces and empty values visible.
SELECT student_id, quote_literal(email) AS email,
       quote_nullable(city) AS city, quote_literal(acquired_via) AS channel
FROM academy.students WHERE student_id BETWEEN 3 AND 7 ORDER BY student_id;

-- PG08. Unpaid orders remain in the source and core.
SELECT lower(trim(status)) AS status, count(*)
FROM academy.orders GROUP BY lower(trim(status)) ORDER BY status;

-- PG09. Data for the exercise: deliveries and logical events are different.
SELECT count(*) AS deliveries, count(DISTINCT event_id) AS logical_events
FROM academy.lesson_events;

-- PG10. Run before and after demo_changes.sql: Kazan becomes Yekaterinburg.
SELECT student_id, city, updated_at FROM academy.students WHERE student_id = 1;

-- PG11. Empty initially; one order after demo_changes.sql, even if applied twice.
SELECT order_id, student_id, ordered_at, status
FROM academy.orders WHERE order_id = 1001;
