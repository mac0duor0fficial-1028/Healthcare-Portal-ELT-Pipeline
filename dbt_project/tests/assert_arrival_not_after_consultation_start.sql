{{ config(severity='warn') }}
select appointment_id, arrived_at, consultation_started_at
from {{ ref('stg_appointments') }}
where arrived_at is not null
  and consultation_started_at is not null
  and consultation_started_at < arrived_at
