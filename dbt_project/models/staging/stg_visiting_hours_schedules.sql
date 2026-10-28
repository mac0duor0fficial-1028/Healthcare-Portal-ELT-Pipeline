with src as (
    {{ latest_batch(source('api', 'raw_visiting_hours_schedules')) }}
),

parsed as (
    select
        {{ mapped_columns('visiting_hours_schedules') }},
        _batch_id,
        _loaded_at
    from src
)

select *
from parsed
where schedule_id is not null
qualify row_number() over (partition by schedule_id order by _loaded_at desc) = 1
