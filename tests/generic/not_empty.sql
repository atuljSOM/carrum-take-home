{#- Fails when the relation has no rows: catches a missing, truncated or header-only extract. -#}
{% test not_empty(model) %}

select 'relation is empty' as failure
where (select count(*) from {{ model }}) = 0

{% endtest %}
