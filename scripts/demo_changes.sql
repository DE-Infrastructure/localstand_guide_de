-- Safe to apply more than once. Show changes propagating through the same DAG.
\set ON_ERROR_STOP on
BEGIN;
UPDATE academy.students SET city = ' Екатеринбург ', updated_at = '2026-04-16 12:00:00+00'
WHERE student_id = 1;
INSERT INTO academy.orders VALUES
    (1001, 1, '2026-04-16 12:00:00+00', 'PAID ', '2026-04-16 12:15:00+00')
ON CONFLICT (order_id) DO NOTHING;
INSERT INTO academy.order_items VALUES
    (10011, 1001, 3, 1490000, 0, '2026-04-16 12:00:00+00'),
    (10012, 1001, 5, 1290000, 0, '2026-04-16 12:00:00+00')
ON CONFLICT (order_item_id) DO NOTHING;
INSERT INTO academy.payments VALUES
    (10011, 1001, 2780000, 'succeeded', '2026-04-16 12:15:00+00', '2026-04-16 12:15:00+00')
ON CONFLICT (payment_id) DO NOTHING;
INSERT INTO academy.enrollments VALUES
    (10011, 10011, '2026-04-16 12:20:00+00', '2026-04-16 12:20:00+00'),
    (10012, 10012, '2026-04-16 12:20:00+00', '2026-04-16 12:20:00+00')
ON CONFLICT (enrollment_id) DO NOTHING;
INSERT INTO academy.lesson_events VALUES
    (2000001, 2000001, 10011, 1, 'lesson_completed', '2026-04-17 10:00:00+00', '2026-04-17 10:00:01+00'),
    (2000002, 2000001, 10011, 1, 'lesson_completed', '2026-04-17 10:00:00+00', '2026-04-17 10:05:00+00')
ON CONFLICT (delivery_id) DO NOTHING;
COMMIT;
