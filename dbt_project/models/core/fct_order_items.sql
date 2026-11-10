{{ config(distributed_by='order_id') }}
-- Grain: one order item. Aggregate 1:N payments and refunds BEFORE joining.
with payments as (
    select order_id, sum(amount_kopecks) as paid_kopecks
    from {{ ref('stg_payments') }} where status = 'succeeded'
    group by order_id
), refunds as (
    select order_item_id, sum(amount_kopecks) as refunded_kopecks
    from {{ ref('stg_refunds') }} where status = 'processed'
    group by order_item_id
), items as (
    select i.order_item_id, i.order_id, o.student_id, i.course_id,
        (o.ordered_at at time zone 'UTC')::date as order_date,
        o.status as order_status,
        i.price_kopecks, i.discount_kopecks,
        i.price_kopecks - i.discount_kopecks as ordered_kopecks,
        coalesce(p.paid_kopecks, 0) > 0 as is_paid,
        case when coalesce(p.paid_kopecks, 0) > 0
            then i.price_kopecks - i.discount_kopecks else 0 end as gross_kopecks,
        coalesce(r.refunded_kopecks, 0) as refunded_kopecks
    from {{ ref('stg_order_items') }} i
    join {{ ref('stg_orders') }} o on i.order_id = o.order_id
    left join payments p on i.order_id = p.order_id
    left join refunds r on i.order_item_id = r.order_item_id
)
select *, gross_kopecks - refunded_kopecks as net_kopecks from items
