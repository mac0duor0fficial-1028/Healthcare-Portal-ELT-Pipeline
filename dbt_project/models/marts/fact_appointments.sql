{#- GRAIN: one row per appointment.  Foreign keys fall back to the 'Unknown' member (-1)
    so no fact row is ever dropped by a join; the share of unknowns is monitored by a test. -#}
with appts as (
    select * from {{ ref('int_appointments_enriched') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['a.appointment_id']) }} as appointment_key,
    a.appointment_id,
    -- dimension keys
    coalesce(p.patient_key, {{ unknown_key() }}) as patient_key,
    coalesce(d.doctor_key, {{ unknown_key() }}) as doctor_key,
    coalesce(c.clinic_key, {{ unknown_key() }}) as clinic_key,
    coalesce(dz.disease_key, {{ unknown_key() }}) as disease_key,
    a.appointment_date as date_key,
    -- degenerate / natural ids (kept for orphan monitoring)
    a.patient_id,
    a.doctor_id,
    a.location_id,
    a.token_no,
    -- descriptors
    a.status,
    a.is_completed,
    a.is_cancelled,
    a.is_no_show,
    a.is_late_arrival,
    a.is_end_time_derived,
    -- timestamps (UTC)
    a.created_at,
    a.start_time,
    a.end_time,
    a.arrived_at,
    a.consultation_started_at,
    a.consultation_ended_at,
    -- measures
    a.scheduled_duration_min,
    a.wait_minutes,
    a.arrival_delay_minutes,
    a.booking_lead_time_hours
from appts as a
left join {{ ref('dim_patients') }} as p on a.patient_id = p.patient_id
left join {{ ref('dim_doctors') }} as d on a.doctor_id = d.doctor_id
left join {{ ref('dim_clinics') }} as c on a.location_id = c.location_id
left join {{ ref('dim_diseases') }} as dz on a.disease_id = dz.disease_id
