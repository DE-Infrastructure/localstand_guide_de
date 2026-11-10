{{ config(distributed_by='course_id') }}
select course_id, title, category, price_kopecks, total_lessons
from {{ ref('stg_courses') }}
