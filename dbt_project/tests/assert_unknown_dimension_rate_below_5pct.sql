{{ config(severity='warn') }}
{#- Orphan monitor: fact rows whose natural id exists but has no dimension row. -#}
with stats as (
    select
        count(*) as total,
        count_if(patient_id is not null and patient_key = {{ unknown_key() }}) as unknown_patients,
        count_if(doctor_id is not null and doctor_key = {{ unknown_key() }}) as unknown_doctors,
        count_if(location_id is not null and clinic_key = {{ unknown_key() }}) as unknown_clinics
    from {{ ref('fact_appointments') }}
)

select *
from stats
where total > 0
  and (
      unknown_patients / total > 0.05
      or unknown_doctors / total > 0.05
      or unknown_clinics / total > 0.05
  )
