with src as (
    {{ latest_batch(source('api', 'raw_patients')) }}
),

parsed as (
    select
        {{ mapped_columns('patients') }},
        _batch_id,
        _loaded_at
    from src
)

select *
from parsed
where patient_id is not null
qualify row_number() over (partition by patient_id order by _loaded_at desc) = 1
