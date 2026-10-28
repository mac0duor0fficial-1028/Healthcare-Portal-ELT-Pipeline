select
    {{ dbt_utils.generate_surrogate_key(['disease_id']) }} as disease_key,
    disease_id,
    disease_name,
    coalesce(is_active, true) as is_active,
    false as is_unknown
from {{ ref('stg_diseases') }}

union all

select {{ unknown_key() }}, -1, 'Unknown', true, true
