select
    payment_id,
    order_id,
    amount_kopecks,
    lower(trim(status)) as status,
    paid_at,
    updated_at,
    _batch_id,
    _loaded_at
from {{ source('academy_raw', 'payments') }}
