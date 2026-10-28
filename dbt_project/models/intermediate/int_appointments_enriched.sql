{#- Business logic lives here (not in the fact) so it can be unit tested in isolation. -#}
with base as (
    select * from {{ ref('stg_appointments') }}
),

derived as (
    select
        *,
        lower(status) in {{ sql_list('completed_statuses') }} as is_completed,
        lower(status) in {{ sql_list('cancelled_statuses') }} as is_cancelled,
        lower(status) in {{ sql_list('no_show_statuses') }} as is_no_show,
        datediff('minute', start_time, end_time) as scheduled_duration_min,
        -- Actual start of care; optionally falls back to scheduled start (see vars)
        coalesce(
            consultation_started_at,
            case when {{ 'true' if var('wait_time_fallback_to_scheduled_start') else 'false' }}
                then start_time end
        ) as service_start_at
    from base
)

select
    *,
    -- Wait = arrival -> start of care. NULL (never negative) when inputs are missing/inconsistent.
    case when arrived_at is not null and service_start_at is not null
              and service_start_at >= arrived_at
         then datediff('minute', arrived_at, service_start_at) end as wait_minutes,
    -- Positive = patient arrived after the scheduled start
    case when arrived_at is not null and start_time is not null
         then datediff('minute', start_time, arrived_at) end as arrival_delay_minutes,
    case when created_at is not null and start_time is not null
         then datediff('hour', created_at, start_time) end as booking_lead_time_hours
from derived
