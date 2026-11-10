select
    student_id,
    trim(full_name) as full_name,
    lower(trim(email)) as email,
    coalesce(nullif(initcap(trim(city)), ''), 'Не указан') as city,
    lower(trim(acquired_via)) as acquired_via,
    registered_at,
    updated_at,
    _batch_id,
    _loaded_at
from {{ source('academy_raw', 'students') }}
