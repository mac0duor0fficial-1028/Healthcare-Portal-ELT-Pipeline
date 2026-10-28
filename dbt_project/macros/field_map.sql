{# Look up one canonical field in vars.field_map and render its extraction SQL. #}
{% macro fm(entity, field, payload='payload') -%}
    {%- set spec = var('field_map')[entity][field] -%}
    {{ json_field(payload, spec['candidates'], spec.get('type', 'string')) }}
{%- endmacro %}

{# Render "<expr> as <canonical_name>" for every field of an entity. #}
{% macro mapped_columns(entity) -%}
    {%- for fname in var('field_map')[entity].keys() %}
    {{ fm(entity, fname) }} as {{ fname }}{{ "," if not loop.last }}
    {%- endfor %}
{%- endmacro %}
