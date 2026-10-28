{#- Extract the first non-null candidate key from a VARIANT payload and cast it safely.
    Each candidate is cast to string BEFORE coalesce so that JSON null (which is a
    non-NULL VARIANT in Snowflake) correctly falls through to the next candidate. -#}
{% macro json_field(payload, candidates, dtype='string') -%}
    {%- set getters = [] -%}
    {%- for c in candidates -%}
        {%- do getters.append("get_ignore_case(" ~ payload ~ ", '" ~ c ~ "')::string") -%}
    {%- endfor -%}
    {%- set raw = "coalesce(" ~ getters | join(", ") ~ ")" -%}
    {%- if dtype == 'string' -%}
        nullif(trim({{ raw }}), '')
    {%- elif dtype == 'int' -%}
        try_to_number({{ raw }})
    {%- elif dtype == 'decimal' -%}
        try_to_decimal({{ raw }}, 18, 4)
    {%- elif dtype == 'boolean' -%}
        try_to_boolean({{ raw }})
    {%- elif dtype == 'date' -%}
        coalesce(try_to_date({{ raw }}), try_to_timestamp_ntz({{ raw }})::date)
    {%- elif dtype == 'timestamp' -%}
        convert_timezone('UTC', try_to_timestamp_tz({{ raw }}))::timestamp_ntz
    {%- else -%}
        {{ exceptions.raise_compiler_error("json_field: unsupported dtype '" ~ dtype ~ "'") }}
    {%- endif -%}
{%- endmacro %}
