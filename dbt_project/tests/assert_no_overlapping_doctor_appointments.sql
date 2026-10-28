{{ config(severity='warn') }}
{#- A doctor cannot be in two non-cancelled appointments at the same time. -#}
select
    a.doctor_id,
    a.appointment_id as appointment_id_a,
    b.appointment_id as appointment_id_b,
    a.start_time as start_a,
    a.end_time as end_a,
    b.start_time as start_b,
    b.end_time as end_b
from {{ ref('int_appointments_enriched') }} as a
inner join {{ ref('int_appointments_enriched') }} as b
    on a.doctor_id = b.doctor_id
    and a.appointment_id < b.appointment_id
    and a.start_time < b.end_time
    and b.start_time < a.end_time
where not a.is_cancelled
  and not b.is_cancelled
