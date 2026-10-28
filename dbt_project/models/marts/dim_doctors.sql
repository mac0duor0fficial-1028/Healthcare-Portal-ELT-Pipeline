with users as (
    select * from {{ ref('stg_users') }}
),

roles as (
    select * from {{ ref('stg_roles') }}
),

doctors as (
    select
        u.user_id as doctor_id,
        u.user_name as doctor_name,
        coalesce(u.role_name, r.role_name) as role_name,
        u.specialization,
        u.location_id as home_location_id,
        coalesce(u.is_active, true) as is_active
    from users as u
    left join roles as r on u.role_id = r.role_id
    {%- if var('doctor_role_names') | length > 0 %}
    where lower(coalesce(u.role_name, r.role_name)) in {{ sql_list('doctor_role_names') }}
    {%- endif %}
)

select
    {{ dbt_utils.generate_surrogate_key(['doctor_id']) }} as doctor_key,
    doctor_id,
    doctor_name,
    role_name,
    specialization,
    home_location_id,
    is_active,
    false as is_unknown
from doctors

union all

select {{ unknown_key() }}, -1, 'Unknown', null, null, null, true, true
