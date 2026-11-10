with totals as (
    select (select coalesce(sum(net_kopecks), 0) from {{ ref('fct_orders') }}) / 100.0 as core_total,
        (select coalesce(sum(net_sales_rub), 0) from {{ ref('mart_sales_daily') }}) as daily_total
)
select * from totals
where core_total <> daily_total
