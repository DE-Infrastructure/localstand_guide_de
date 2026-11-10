select
    order_id,
    student_id,
    ordered_at,
    lower(trim(status)) as status,
    updated_at,
    _batch_id,
    _loaded_at
from {{ source('academy_raw', 'orders') }}
