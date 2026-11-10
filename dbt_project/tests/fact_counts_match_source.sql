select 'orders' as entity
where (select count(*) from {{ ref('fct_orders') }})
   <> (select count(*) from {{ ref('stg_orders') }})
union all
select 'items'
where (select count(*) from {{ ref('fct_order_items') }})
   <> (select count(*) from {{ ref('stg_order_items') }})
