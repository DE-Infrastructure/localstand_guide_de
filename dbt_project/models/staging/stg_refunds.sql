select
    refund_id,
    order_item_id,
    amount_kopecks,
    lower(trim(status)) as status,
    refunded_at,
    updated_at,
    _batch_id,
    _loaded_at
from {{ source('academy_raw', 'refunds') }}
