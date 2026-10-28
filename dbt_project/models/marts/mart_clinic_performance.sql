select
    f.clinic_key,
    c.clinic_name,
    date_trunc('month', f.date_key)::date as month_start,
    count(*) as total_appointments,
    count_if(f.is_completed) as completed,
    count_if(f.is_cancelled) as cancelled,
    count_if(f.is_no_show) as no_shows,
    round(div0null(count_if(f.is_completed), count(*)), 4) as completion_rate,
    round(div0null(count_if(f.is_cancelled), count(*)), 4) as cancellation_rate,
    round(div0null(count_if(f.is_no_show), count(*)), 4) as no_show_rate,
    round(avg(f.wait_minutes), 1) as avg_wait_minutes,
    percentile_cont(0.9) within group (order by f.wait_minutes) as p90_wait_minutes,
    round(avg(f.arrival_delay_minutes), 1) as avg_arrival_delay_minutes,
    round(avg(f.scheduled_duration_min), 1) as avg_scheduled_duration_min,
    count(distinct f.patient_key) as unique_patients,
    count(distinct f.doctor_key) as active_doctors
from {{ ref('fact_appointments') }} as f
inner join {{ ref('dim_clinics') }} as c on f.clinic_key = c.clinic_key
group by 1, 2, 3
