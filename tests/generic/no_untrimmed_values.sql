{#- Fails on values with leading or trailing whitespace. -#}
{% test no_untrimmed_values(model, column_name) %}

select {{ column_name }} as invalid_value, count(*) as n_rows
from {{ model }}
where {{ column_name }} <> trim({{ column_name }})
group by 1

{% endtest %}
