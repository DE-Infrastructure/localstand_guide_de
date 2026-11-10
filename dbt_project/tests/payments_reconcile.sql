-- This demo supports full payment, including several successful installments.
-- An order with a partial payment must fail instead of overstating sales.
with paid as (
    select order_id, sum(amount_kopecks) as paid_kopecks
    from {{ ref('stg_payments') }} where status = 'succeeded' group by order_id
)
select o.order_id
from {{ ref('fct_orders') }} o
left join paid p on o.order_id = p.order_id
where o.gross_kopecks <> coalesce(p.paid_kopecks, 0)
   or (o.order_status = 'paid') <> o.is_paid
