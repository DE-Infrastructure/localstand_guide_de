with batches as (
    {% for table in ['students', 'courses', 'orders', 'order_items', 'payments', 'refunds', 'enrollments', 'lesson_events'] %}
    select _batch_id from {{ source('academy_raw', table) }}
    {% if not loop.last %} union all {% endif %}
    {% endfor %}
)
select count(distinct _batch_id) as batch_count from batches
having count(distinct _batch_id) <> 1
