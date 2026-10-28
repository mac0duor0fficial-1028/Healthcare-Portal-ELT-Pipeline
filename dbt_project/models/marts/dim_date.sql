with spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ var('date_spine_start') ~ "' as date)",
        end_date="dateadd(year, 2, current_date())"
    ) }}
)

select
    cast(date_day as date) as date_day,
    year(date_day) as year,
    quarter(date_day) as quarter,
    month(date_day) as month,
    monthname(date_day) as month_name,
    date_trunc('week', date_day)::date as week_start,
    date_trunc('month', date_day)::date as month_start,
    dayofweekiso(date_day) as day_of_week_iso,
    dayname(date_day) as day_name,
    dayofweekiso(date_day) in (6, 7) as is_weekend
from spine
