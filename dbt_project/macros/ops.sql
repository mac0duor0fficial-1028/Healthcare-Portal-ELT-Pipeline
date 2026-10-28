{# dbt run-operation drop_ci_schema --target ci  (used by CI cleanup; refuses non-ci targets) #}
{% macro drop_ci_schema() %}
    {% if target.name != 'ci' %}
        {{ exceptions.raise_compiler_error("drop_ci_schema may only run against the 'ci' target") }}
    {% endif %}
    {% do run_query("drop schema if exists " ~ target.database ~ "." ~ target.schema ~ " cascade") %}
    {{ log("Dropped schema " ~ target.database ~ "." ~ target.schema, info=True) }}
{% endmacro %}

{# dbt run-operation assert_field_coverage
   Fails loudly if a *required* canonical field resolves to NULL for every row of the latest
   RAW batch, i.e. the field_map candidates do not match the real API. Prevents silent NULL columns. #}
{% macro assert_field_coverage() %}
    {% if execute %}
        {% set problems = [] %}
        {% for entity, fields in var('field_map').items() %}
            {% set rel = source('api', 'raw_' ~ entity) %}
            {% for fname, spec in fields.items() %}
                {% if spec.get('required', false) %}
                    {% set q %}
                        select count(*) as total, count_if({{ fm(entity, fname) }} is not null) as populated
                        from ({{ latest_batch(rel) }})
                    {% endset %}
                    {% set res = run_query(q).rows[0] %}
                    {% if res[0] == 0 %}
                        {% do problems.append(entity ~ ": RAW table is empty") %}
                    {% elif res[1] == 0 %}
                        {% do problems.append(entity ~ "." ~ fname ~ ": no candidate matched (" ~ spec['candidates'] | join(', ') ~ ")") %}
                    {% else %}
                        {{ log("OK  " ~ entity ~ "." ~ fname ~ "  " ~ res[1] ~ "/" ~ res[0] ~ " populated", info=True) }}
                    {% endif %}
                {% endif %}
            {% endfor %}
        {% endfor %}
        {% if problems | length > 0 %}
            {{ exceptions.raise_compiler_error("Field mapping problems:\n - " ~ problems | join("\n - ")) }}
        {% endif %}
    {% endif %}
{% endmacro %}
