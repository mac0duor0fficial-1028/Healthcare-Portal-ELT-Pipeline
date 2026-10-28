with src as (
    {{ latest_batch(source('api', 'raw_diseases')) }}
),

parsed as (
    select
        {{ mapped_columns('diseases') }},
        _batch_id,
        _loaded_at
    from src
)

select *
from parsed
where disease_id is not null
qualify row_number() over (partition by disease_id order by _loaded_at desc) = 1
