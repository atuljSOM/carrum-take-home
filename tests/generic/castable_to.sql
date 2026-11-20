{#- Fails on non-null text values that DuckDB cannot cast to `data_type` (e.g. double, date, timestamp).
    Used on bronze, where every column is VARCHAR, to prove silver's casts will succeed. -#}
{% test castable_to(model, column_name, data_type) %}

select {{ column_name }} as invalid_value, count(*) as n_rows
from {{ model }}
where {{ column_name }} is not null
  and try_cast({{ column_name }} as {{ data_type }}) is null
group by 1

{% endtest %}
