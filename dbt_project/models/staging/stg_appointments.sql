with src as (
    {{ latest_batch(source('api', 'raw_appointments')) }}
),

parsed as (
    select
        {{ mapped_columns('appointments') }},
        _batch_id,
        _loaded_at
    from src
),

timed as (
    select
        *,
        coalesce(start_ts, {{ clock_to_ts('appointment_date', 'start_clock') }}) as start_time,
        coalesce(end_ts, {{ clock_to_ts('appointment_date', 'end_clock') }}) as end_time_source
    from parsed
    where appointment_id is not null
)

select
    appointment_id,
    patient_id,
    doctor_id,
    location_id,
    disease_id,
    schedule_id,
    appointment_date,
    start_time,
    {%- if var('default_slot_minutes') %}
    coalesce(end_time_source, dateadd(minute, {{ var('default_slot_minutes') | int }}, start_time)) as end_time,
    {%- else %}
    end_time_source as end_time,
    {%- endif %}
    (end_time_source is null and start_time is not null) as is_end_time_derived,
    lower(status) as status,
    arrived_at,
    consultation_started_at,
    consultation_ended_at,
    token_no,
    is_late_arrival,
    created_at,
    _batch_id,
    _loaded_at
from timed
qualify row_number() over (partition by appointment_id order by _loaded_at desc) = 1
