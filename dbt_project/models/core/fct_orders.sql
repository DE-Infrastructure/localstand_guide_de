{{ config(distributed_by='order_id') }}
-- Grain: one order, including pending and cancelled orders.
select order_id, student_id, order_date, order_status,
    count(*) as item_count,
    bool_or(is_paid) as is_paid,
    sum(ordered_kopecks) as ordered_kopecks,
    sum(gross_kopecks) as gross_kopecks,
    sum(refunded_kopecks) as refunded_kopecks,
    sum(net_kopecks) as net_kopecks
from {{ ref('fct_order_items') }}
group by order_id, student_id, order_date, order_status
