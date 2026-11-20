{{ config(alias='stg_contract_fee_schedule') }}

-- One row per contract fee line. Casts types; no other change.
-- discount_pct is kept exactly as entered: its scale (fraction vs whole percent) is a business
-- interpretation and is resolved in gold (gold_dim_fee_lines).
select
    trim(fee_id)                              as fee_id,
    nullif(trim(program_id), '')              as program_id,
    trim(fee_type)                            as fee_type,
    cast(rate as decimal(12, 2))              as rate_usd,
    cast(projected_episodes as double)        as projected_episodes,
    cast(nullif(trim(discount_pct), '') as double) as discount_pct_raw,
    cast(effective_start as date)             as effective_start,
    cast(effective_end as date)               as effective_end
from {{ ref('bronze_contract_fee_schedule') }}
