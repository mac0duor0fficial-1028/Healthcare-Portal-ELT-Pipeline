with src as (
    {{ latest_batch(source('api', 'raw_users')) }}
),

parsed as (
    select
        {{ mapped_columns('users') }},
        _batch_id,
        _loaded_at
    from src
)

select *
from parsed
where user_id is not null
qualify row_number() over (partition by user_id order by _loaded_at desc) = 1
