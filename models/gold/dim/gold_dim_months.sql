{{ config(alias='dim_months') }}

-- Grain: one row per calendar month. Rules and columns: see the model's yml.

with bounds as (
    select
        date_trunc('month', min(effective_start)) as first_month,
        date_trunc('month', max(effective_end))   as last_month
    from {{ ref('silver_stg_contract_fee_schedule') }}
)

select
    cast(month_start as date)                                     as month_start,
    cast(last_day(month_start) as date)                           as month_end,
    year(month_start)                                             as year,
    quarter(month_start)                                          as quarter,
    year(month_start) || '-Q' || quarter(month_start)             as year_quarter,
    strftime(month_start, '%Y-%m')                                as year_month,
    month_start <= cast('{{ var("as_of_date") }}' as date)       as is_on_or_before_as_of
from bounds,
     unnest(generate_series(first_month, last_month, interval 1 month)) as t(month_start)
