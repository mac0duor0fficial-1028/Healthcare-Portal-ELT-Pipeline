{# RAW is append-only (one full snapshot per run). The current state of a table is its
   newest batch, which also correctly drops records deleted at the source. #}
{% macro latest_batch(relation) -%}
    select payload, _batch_id, _loaded_at
    from {{ relation }}
    where _loaded_at = (select max(_loaded_at) from {{ relation }})
{%- endmacro %}
