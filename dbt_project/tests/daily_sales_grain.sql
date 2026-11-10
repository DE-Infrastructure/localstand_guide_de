select order_date, course_id from {{ ref('mart_sales_daily') }}
group by order_date, course_id having count(*) <> 1
