with src as (
    {{ latest_batch(source('api', 'raw_roles')) }}
),

parsed as (
    select
        {{ mapped_columns('roles') }},
        _batch_id,
        _loaded_at
    from src
)

select *
from parsed
where role_id is not null
qualify row_number() over (partition by role_id order by _loaded_at desc) = 1
