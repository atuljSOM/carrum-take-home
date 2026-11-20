{{ config(alias='stg_care_platform_episodes') }}

-- Grain: one row per distinct episode status record. Rules and columns: see the model's yml.

with deduped as (
    select
        episode_id, member_id, fee_id, procedure_category, provider_id,
        surgery_date, episode_status, invoice_month, record_updated_at,
        count(*) as source_row_count
    from {{ ref('bronze_care_platform_episodes') }}
    group by all
)

select
    trim(episode_id)                                    as episode_id,
    trim(episode_id) || '|' || record_updated_at        as episode_record_id,
    trim(member_id)                                     as member_id,
    trim(fee_id)                                        as fee_id,
    trim(procedure_category)                            as procedure_category,
    trim(provider_id)                                   as provider_id,
    coalesce(
        try_cast(surgery_date as date),
        cast(try_strptime(surgery_date, '%m/%d/%Y') as date)
    )                                                   as surgery_date,
    case
        when surgery_date is null                     then null
        when try_cast(surgery_date as date) is not null then 'YYYY-MM-DD'
        else 'MM/DD/YYYY'
    end                                                 as surgery_date_source_format,
    trim(episode_status)                                as episode_status,
    cast(strptime(invoice_month, '%Y-%m') as date)      as invoice_month,
    cast(record_updated_at as timestamp)                as record_updated_at,
    source_row_count,
    source_row_count > 1                                as is_duplicated_in_source,
    cast(record_updated_at as date) > cast('{{ var("as_of_date") }}' as date)
                                                        as is_recorded_after_as_of,
    (provider_id = 'PRV-TEST' or member_id like 'TEST-%') as is_test_record
from deduped
