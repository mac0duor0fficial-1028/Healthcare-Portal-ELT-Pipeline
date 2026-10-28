{{ config(severity='warn') }}
{#- Reconciliation: rows staged == rows extracted in the latest successful load.
    A mismatch means duplicates or NULL primary keys were dropped in staging. -#}
with latest_log as (
    select endpoint, row_count
    from {{ source('api', 'extract_log') }}
    where status = 'SUCCESS'
    qualify row_number() over (partition by endpoint order by loaded_at desc) = 1
),

staged as (
    select 'appointments' as endpoint, count(*) as staged_rows from {{ ref('stg_appointments') }}
    union all select 'patients', count(*) from {{ ref('stg_patients') }}
    union all select 'users', count(*) from {{ ref('stg_users') }}
    union all select 'roles', count(*) from {{ ref('stg_roles') }}
    union all select 'locations', count(*) from {{ ref('stg_locations') }}
    union all select 'diseases', count(*) from {{ ref('stg_diseases') }}
    union all select 'visiting-hours-schedules', count(*) from {{ ref('stg_visiting_hours_schedules') }}
)

select
    s.endpoint,
    l.row_count as extracted_rows,
    s.staged_rows
from staged as s
inner join latest_log as l on s.endpoint = l.endpoint
where s.staged_rows != l.row_count
