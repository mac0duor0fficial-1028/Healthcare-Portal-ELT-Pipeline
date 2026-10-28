{{ config(severity='warn') }}
{#- Surfaces statuses the flag logic does not know about, so KPIs are never silently wrong.
    Add new values to the *_statuses vars in dbt_project.yml. -#}
select status, count(*) as appointments
from {{ ref('stg_appointments') }}
where status not in {{ sql_list('completed_statuses') }}
  and status not in {{ sql_list('cancelled_statuses') }}
  and status not in {{ sql_list('no_show_statuses') }}
  and status not in {{ sql_list('open_statuses') }}
group by 1
