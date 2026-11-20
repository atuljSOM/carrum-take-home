{{ config(alias='dim_fee_lines') }}

-- Grain: one row per contract fee line. Rules and columns: see the model's yml.

with fee_lines as (
    select * from {{ ref('silver_stg_contract_fee_schedule') }}
),

programs as (
    select * from {{ ref('gold_dim_programs') }}
)

select
    fee_lines.fee_id,
    fee_lines.fee_type,
    fee_lines.program_id,
    programs.program_name,
    programs.service_line,
    coalesce(programs.employer_id, 'UNATTRIBUTED')                      as employer_id,
    coalesce(programs.employer_name, 'Unattributed (no valid program)') as employer_name,
    fee_lines.rate_usd,
    fee_lines.discount_pct_raw,
    case
        when fee_lines.discount_pct_raw is null then 0.0
        when fee_lines.discount_pct_raw > 1     then fee_lines.discount_pct_raw / 100
        else fee_lines.discount_pct_raw
    end                                                                 as discount_rate,
    case
        when fee_lines.discount_pct_raw is null then 'blank as zero'
        when fee_lines.discount_pct_raw > 1     then 'whole percent / 100'
        else 'fraction as entered'
    end                                                                 as discount_rule_applied,
    fee_lines.projected_episodes,
    fee_lines.effective_start,
    fee_lines.effective_end,
    datediff('month', date_trunc('month', fee_lines.effective_start),
                      date_trunc('month', fee_lines.effective_end)) + 1 as effective_months,
    programs.program_id is null                                         as is_orphan
from fee_lines
left join programs on programs.program_id = fee_lines.program_id
