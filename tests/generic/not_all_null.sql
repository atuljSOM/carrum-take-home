{#- For columns that may legitimately be null on some rows: fails only when the column is
    null on every row, which usually means an upstream job stopped populating it. -#}
{% test not_all_null(model, column_name) %}

select 'column is null on every row' as failure
where (select count({{ column_name }}) from {{ model }}) = 0
  and (select count(*) from {{ model }}) > 0

{% endtest %}
