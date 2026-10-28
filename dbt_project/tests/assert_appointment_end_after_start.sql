{{ config(severity='error', tags=['critical']) }}
{#- Critical rule: an appointment's end_time must be strictly after its start_time.
    Runs on STAGING so a violation blocks every downstream model in `dbt build`. -#}
select
    appointment_id,
    patient_id,
    doctor_id,
    start_time,
    end_time
from {{ ref('stg_appointments') }}
where start_time is not null
  and end_time is not null
  and end_time <= start_time
