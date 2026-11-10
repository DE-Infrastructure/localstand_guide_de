select
    course_id,
    trim(title) as title,
    lower(trim(category)) as category,
    price_kopecks,
    total_lessons,
    updated_at,
    _batch_id,
    _loaded_at
from {{ source('academy_raw', 'courses') }}
