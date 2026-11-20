{#- Fails on non-null values that do not fully match `regex`. Catches ID-format drift,
    stray whitespace in keys, and date/month formats the downstream parsers do not handle. -#}
{% test matches_pattern(model, column_name, regex) %}

select {{ column_name }} as invalid_value, count(*) as n_rows
from {{ model }}
where {{ column_name }} is not null
  and not regexp_full_match({{ column_name }}, '{{ regex }}')
group by 1

{% endtest %}
