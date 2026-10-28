with src as (
    {{ latest_batch(source('api', 'raw_locations')) }}
),

parsed as (
    select
        {{ mapped_columns('locations') }},
        _batch_id,
        _loaded_at
    from src
)

select *
from parsed
where location_id is not null
qualify row_number() over (partition by location_id order by _loaded_at desc) = 1
