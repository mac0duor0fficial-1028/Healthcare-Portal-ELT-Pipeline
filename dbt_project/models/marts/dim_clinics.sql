select
    {{ dbt_utils.generate_surrogate_key(['location_id']) }} as clinic_key,
    location_id,
    location_name as clinic_name,
    city,
    address,
    coalesce(is_active, true) as is_active,
    false as is_unknown
from {{ ref('stg_locations') }}

union all

select {{ unknown_key() }}, -1, 'Unknown', null, null, true, true
