select
    order_item_id,
    order_id,
    course_id,
    price_kopecks,
    discount_kopecks,
    updated_at,
    _batch_id,
    _loaded_at
from {{ source('academy_raw', 'order_items') }}
