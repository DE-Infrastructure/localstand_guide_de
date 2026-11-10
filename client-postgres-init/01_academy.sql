\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA academy;

CREATE TABLE academy.students (
    student_id integer PRIMARY KEY,
    full_name text NOT NULL,
    email text NOT NULL,
    city text,
    acquired_via text NOT NULL,
    registered_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE TABLE academy.courses (
    course_id integer PRIMARY KEY,
    title text NOT NULL,
    category text NOT NULL,
    price_kopecks bigint NOT NULL CHECK (price_kopecks > 0),
    total_lessons integer NOT NULL CHECK (total_lessons > 0),
    updated_at timestamptz NOT NULL
);
CREATE TABLE academy.orders (
    order_id integer PRIMARY KEY,
    student_id integer NOT NULL REFERENCES academy.students,
    ordered_at timestamptz NOT NULL,
    status text NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE TABLE academy.order_items (
    order_item_id integer PRIMARY KEY,
    order_id integer NOT NULL REFERENCES academy.orders,
    course_id integer NOT NULL REFERENCES academy.courses,
    price_kopecks bigint NOT NULL CHECK (price_kopecks > 0),
    discount_kopecks bigint NOT NULL CHECK (discount_kopecks >= 0 AND discount_kopecks < price_kopecks),
    updated_at timestamptz NOT NULL,
    UNIQUE (order_id, course_id)
);
CREATE TABLE academy.payments (
    payment_id integer PRIMARY KEY,
    order_id integer NOT NULL REFERENCES academy.orders,
    amount_kopecks bigint NOT NULL CHECK (amount_kopecks > 0),
    status text NOT NULL,
    paid_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE TABLE academy.refunds (
    refund_id integer PRIMARY KEY,
    order_item_id integer NOT NULL REFERENCES academy.order_items,
    amount_kopecks bigint NOT NULL CHECK (amount_kopecks > 0),
    status text NOT NULL,
    refunded_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE TABLE academy.enrollments (
    enrollment_id integer PRIMARY KEY,
    order_item_id integer NOT NULL UNIQUE REFERENCES academy.order_items,
    enrolled_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
-- delivery_id identifies a delivery; event_id identifies a logical lesson event.
-- A repeated delivery keeps event_id but receives a new delivery_id.
CREATE TABLE academy.lesson_events (
    delivery_id bigint PRIMARY KEY,
    event_id bigint NOT NULL,
    enrollment_id integer NOT NULL REFERENCES academy.enrollments,
    lesson_no integer NOT NULL CHECK (lesson_no > 0),
    event_type text NOT NULL,
    event_at timestamptz NOT NULL,
    received_at timestamptz NOT NULL
);

INSERT INTO academy.courses VALUES
    (1, 'SQL с нуля', 'Databases', 490000, 10, '2025-12-01 00:00:00+00'),
    (2, 'Python для инженера данных', 'Programming', 990000, 14, '2025-12-01 00:00:00+00'),
    (3, 'Проектирование DWH', 'Architecture', 1490000, 12, '2025-12-01 00:00:00+00'),
    (4, 'Airflow на практике', 'Orchestration', 790000, 8, '2025-12-01 00:00:00+00'),
    (5, 'dbt и аналитические модели', 'Analytics', 1290000, 10, '2025-12-01 00:00:00+00'),
    (6, 'Greenplum для DE', 'Databases', 1990000, 16, '2025-12-01 00:00:00+00');

INSERT INTO academy.students
SELECT i,
       (ARRAY['Анна', 'Иван', 'Мария', 'Алексей', 'Дарья', 'Михаил'])[1 + i % 6]
           || ' Студент ' || i,
       CASE WHEN i % 7 = 0 THEN '  STUDENT' || i || '@EXAMPLE.COM '
            ELSE 'student' || i || '@example.com' END,
       (ARRAY[' Москва ', 'Казань', 'санкт-петербург', '', NULL, 'Новосибирск'])[1 + i % 6],
       (ARRAY['YouTube ', 'telegram', ' ORGANIC', 'Referral'])[1 + i % 4],
       '2025-12-01 00:00:00+00'::timestamptz + (i % 30) * interval '1 day',
       '2025-12-31 00:00:00+00'::timestamptz
FROM generate_series(1, 200) AS s(i);

INSERT INTO academy.orders
SELECT i, 1 + (i * 37) % 200,
       '2026-01-01 00:00:00+00'::timestamptz + ((i * 13) % 90) * interval '1 day'
           + (i % 20) * interval '1 hour',
       CASE WHEN i % 10 = 0 THEN 'Cancelled' WHEN i % 10 = 1 THEN ' pending '
            ELSE 'PAID ' END,
       '2026-04-01 00:00:00+00'::timestamptz
FROM generate_series(1, 400) AS s(i);

INSERT INTO academy.order_items
SELECT o.order_id * 10 + p.pos, o.order_id, c.course_id, c.price_kopecks,
       CASE WHEN o.order_id % 4 = 0 THEN c.price_kopecks / 10 ELSE 0 END,
       o.updated_at
FROM academy.orders o
CROSS JOIN generate_series(1, 2) AS p(pos)
JOIN academy.courses c ON c.course_id = 1 + (o.order_id + p.pos - 2) % 6;

INSERT INTO academy.payments
SELECT o.order_id * 10 + 1, o.order_id, sum(i.price_kopecks - i.discount_kopecks),
       'Succeeded ', o.ordered_at + interval '15 minutes', o.updated_at
FROM academy.orders o JOIN academy.order_items i USING (order_id)
WHERE lower(trim(o.status)) = 'paid'
GROUP BY o.order_id, o.ordered_at, o.updated_at;
INSERT INTO academy.payments
SELECT payment_id - 1, order_id, amount_kopecks, ' failed',
       paid_at - interval '10 minutes', updated_at
FROM academy.payments WHERE order_id % 7 = 0;

INSERT INTO academy.refunds
SELECT o.order_id, i.order_item_id, (i.price_kopecks - i.discount_kopecks) / 2,
       CASE WHEN o.order_id % 11 = 0 THEN 'PROCESSED ' ELSE 'requested' END,
       o.ordered_at + interval '5 days', o.updated_at + interval '5 days'
FROM academy.orders o JOIN academy.order_items i USING (order_id)
WHERE lower(trim(o.status)) = 'paid' AND i.order_item_id % 10 = 1
  AND (o.order_id % 11 = 0 OR o.order_id % 13 = 0);

INSERT INTO academy.enrollments
SELECT i.order_item_id, i.order_item_id, o.ordered_at + interval '20 minutes', o.updated_at
FROM academy.orders o JOIN academy.order_items i USING (order_id)
WHERE lower(trim(o.status)) = 'paid';

INSERT INTO academy.lesson_events
SELECT e.enrollment_id::bigint * 100 + l.lesson_no,
       e.enrollment_id::bigint * 100 + l.lesson_no,
       e.enrollment_id, l.lesson_no, ' Lesson_Completed ',
       e.enrolled_at + l.lesson_no * interval '1 day',
       e.enrolled_at + l.lesson_no * interval '1 day' + interval '1 minute'
FROM academy.enrollments e
JOIN academy.order_items i USING (order_item_id)
JOIN academy.courses c USING (course_id)
CROSS JOIN generate_series(1, 16) AS l(lesson_no)
WHERE e.enrollment_id % 7 <> 0
  AND l.lesson_no <= least(c.total_lessons, 2 + e.enrollment_id % 11);
INSERT INTO academy.lesson_events
SELECT delivery_id + 1000000, event_id, enrollment_id, lesson_no, event_type,
       event_at, received_at + interval '1 hour'
FROM academy.lesson_events WHERE event_id % 5 = 0;
COMMIT;
