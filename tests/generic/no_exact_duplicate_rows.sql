{#- Fails on rows that are identical in every column (re-delivered or double-written records).
    Bronze keeps them as delivered; this test reports them so silver can remove them. -#}
{% test no_exact_duplicate_rows(model) %}

select *, count(*) as n_copies
from {{ model }}
group by all
having count(*) > 1

{% endtest %}
