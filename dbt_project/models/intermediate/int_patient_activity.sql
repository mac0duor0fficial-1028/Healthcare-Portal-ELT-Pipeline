{#- Activity events available from the API. There is no login/session endpoint, so
    "active" = booked an appointment or arrived for one. This is a proxy; see README. -#}
select
    patient_id,
    appointment_id,
    'booking' as activity_type,
    cast(created_at as date) as activity_date
from {{ ref('int_appointments_enriched') }}
where patient_id is not null and created_at is not null

union all

select
    patient_id,
    appointment_id,
    'arrival' as activity_type,
    cast(arrived_at as date) as activity_date
from {{ ref('int_appointments_enriched') }}
where patient_id is not null and arrived_at is not null
