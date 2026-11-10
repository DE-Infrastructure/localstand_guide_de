{{ config(distributed_by='course_id') }}
-- Grain: UTC order date × course. Refunds are attributed to the original order.
select i.order_date, i.course_id, c.title as course_title,
    count(distinct i.order_id) as paid_orders,
    count(*) as sold_items,
    sum(i.gross_kopecks) / 100.0 as gross_sales_rub,
    sum(i.refunded_kopecks) / 100.0 as refunds_rub,
    sum(i.net_kopecks) / 100.0 as net_sales_rub
from {{ ref('fct_order_items') }} i
join {{ ref('dim_courses') }} c on i.course_id = c.course_id
where i.is_paid
group by i.order_date, i.course_id, c.title
