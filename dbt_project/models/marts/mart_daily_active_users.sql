{#- DAU (proxy): distinct patients who booked OR arrived for an appointment that day. -#}
with events as (
    select * from {{ ref('int_patient_activity') }}
),

first_seen as (
    select patient_id, min(activity_date) as first_activity_date
    from events
    group by 1
),

daily as (
    select
        e.activity_date as date_day,
        count(distinct e.patient_id) as daily_active_users,
        count(distinct case when e.activity_type = 'booking' then e.patient_id end) as booking_users,
        count(distinct case when e.activity_type = 'arrival' then e.patient_id end) as arrival_users,
        count(distinct case when f.first_activity_date = e.activity_date then e.patient_id end) as new_users
    from events as e
    inner join first_seen as f on e.patient_id = f.patient_id
    group by 1
)

select
    date_day,
    daily_active_users,
    booking_users,
    arrival_users,
    new_users,
    daily_active_users - new_users as returning_users,
    round(avg(daily_active_users) over (order by date_day rows between 6 preceding and current row), 2) as dau_7d_avg
from daily
