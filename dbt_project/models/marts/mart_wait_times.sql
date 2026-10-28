select
    f.date_key as date_day,
    f.clinic_key,
    c.clinic_name,
    count(*) as appointments,
    count(f.wait_minutes) as appointments_with_wait,
    round(avg(f.wait_minutes), 1) as avg_wait_minutes,
    median(f.wait_minutes) as median_wait_minutes,
    percentile_cont(0.9) within group (order by f.wait_minutes) as p90_wait_minutes,
    max(f.wait_minutes) as max_wait_minutes
from {{ ref('fact_appointments') }} as f
inner join {{ ref('dim_clinics') }} as c on f.clinic_key = c.clinic_key
group by 1, 2, 3
