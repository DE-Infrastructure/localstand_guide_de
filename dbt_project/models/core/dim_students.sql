{{ config(distributed_by='student_id') }}
select student_id, full_name, email, city, acquired_via, registered_at, updated_at
from {{ ref('stg_students') }}
