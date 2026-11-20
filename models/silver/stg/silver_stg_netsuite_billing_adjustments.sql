{{ config(alias='stg_netsuite_billing_adjustments') }}

-- Grain: one row per distinct NetSuite memo. Rules and columns: see the model's yml.

with deduped as (
    select
        memo_id, program_id, billing_month, adjustment_usd, reason, posted_date,
        count(*) as source_row_count
    from {{ ref('bronze_netsuite_billing_adjustments') }}
    group by all
)

select
    trim(memo_id)                                  as memo_id,
    trim(program_id)                               as program_id,
    case
        when regexp_full_match(trim(billing_month), '\d{4}-\d{1,2}')
            then make_date(cast(split_part(trim(billing_month), '-', 1) as integer),
                           cast(split_part(trim(billing_month), '-', 2) as integer), 1)
        when regexp_full_match(trim(billing_month), '\d{2}/\d{4}')
            then make_date(cast(split_part(trim(billing_month), '/', 2) as integer),
                           cast(split_part(trim(billing_month), '/', 1) as integer), 1)
    end                                            as billing_month,
    case
        when regexp_full_match(trim(billing_month), '\d{4}-\d{2}') then 'YYYY-MM'
        when regexp_full_match(trim(billing_month), '\d{4}-\d{1}')  then 'YYYY-M'
        when regexp_full_match(trim(billing_month), '\d{2}/\d{4}') then 'MM/YYYY'
    end                                            as billing_month_source_format,
    cast(adjustment_usd as decimal(12, 2))         as adjustment_usd,
    trim(reason)                                   as reason,
    cast(posted_date as date)                      as posted_date,
    source_row_count,
    source_row_count > 1                           as is_duplicated_in_source,
    cast(posted_date as date) > cast('{{ var("as_of_date") }}' as date)
                                                   as is_posted_after_as_of
from deduped
