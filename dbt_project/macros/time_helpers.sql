{# Combine a DATE column and a clock string ("09:30", "09:30:00", "09:30 AM") into a timestamp. #}
{% macro clock_to_ts(date_col, clock_col) -%}
    coalesce(
        try_to_timestamp_ntz(to_char({{ date_col }}, 'YYYY-MM-DD') || ' ' || {{ clock_col }}),
        try_to_timestamp_ntz(to_char({{ date_col }}, 'YYYY-MM-DD') || ' ' || {{ clock_col }}, 'YYYY-MM-DD HH12:MI AM'),
        try_to_timestamp_ntz(to_char({{ date_col }}, 'YYYY-MM-DD') || ' ' || {{ clock_col }}, 'YYYY-MM-DD HH12:MI:SS AM')
    )
{%- endmacro %}

{# Surrogate key reserved for the "Unknown" dimension member (natural id = -1). #}
{% macro unknown_key() -%}
    {{ dbt_utils.generate_surrogate_key(["-1"]) }}
{%- endmacro %}

{# Render a SQL list literal from a project var. #}
{% macro sql_list(var_name) -%}
    ({{ "'" ~ var(var_name) | join("', '") ~ "'" }})
{%- endmacro %}
