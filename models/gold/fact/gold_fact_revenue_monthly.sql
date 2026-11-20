{{ config(alias='fact_revenue_monthly') }}

-- Grain: one row per revenue_component x fee line (program for adjustments) x month. Rules and columns: see the model's yml.

with fee_lines as (
    select * from {{ ref('gold_dim_fee_lines') }}
),

months as (
    select * from {{ ref('gold_dim_months') }} where is_on_or_before_as_of
),

programs as (
    select * from {{ ref('gold_dim_programs') }}
),

case_rate as (
    select
        'CASE_RATE'                       as revenue_component,
        episodes.fee_id,
        episodes.surgery_month            as revenue_month,
        count(*)                          as episode_count
    from {{ ref('gold_fact_episodes') }} as episodes
    where episodes.is_revenue_eligible
      and episodes.surgery_month <= cast('{{ var("as_of_date") }}' as date)
    group by all
),

case_rate_priced as (
    select
        case_rate.revenue_component,
        case_rate.fee_id,
        fee_lines.program_id,
        fee_lines.employer_id,
        fee_lines.employer_name,
        case_rate.revenue_month,
        case_rate.episode_count,
        cast(null as integer)                                 as memo_count,
        fee_lines.rate_usd,
        fee_lines.discount_rate,
        case_rate.episode_count * fee_lines.rate_usd           as gross_usd
    from case_rate
    join fee_lines on fee_lines.fee_id = case_rate.fee_id
),

platform_fee as (
    select
        'PLATFORM_FEE'                    as revenue_component,
        fee_lines.fee_id,
        fee_lines.program_id,
        fee_lines.employer_id,
        fee_lines.employer_name,
        months.month_start                as revenue_month,
        cast(null as integer)             as episode_count,
        cast(null as integer)             as memo_count,
        fee_lines.rate_usd,
        fee_lines.discount_rate,
        fee_lines.rate_usd                as gross_usd
    from fee_lines
    join months
      on months.month_start between date_trunc('month', fee_lines.effective_start)
                                and fee_lines.effective_end
    where fee_lines.fee_type = 'PLATFORM_FEE'
),

adjustments as (
    select
        'ADJUSTMENT'                                                      as revenue_component,
        cast(null as varchar)                                             as fee_id,
        memos.program_id,
        coalesce(programs.employer_id, 'UNATTRIBUTED')                    as employer_id,
        coalesce(programs.employer_name, 'Unattributed (no valid program)') as employer_name,
        memos.billing_month                                               as revenue_month,
        cast(null as integer)                                             as episode_count,
        count(*)                                                          as memo_count,
        cast(null as decimal(12, 2))                                      as rate_usd,
        0.0                                                               as discount_rate,
        sum(memos.adjustment_usd)                                         as gross_usd,
        count(*) filter (where memos.is_posted_after_as_of)               as adjustment_memos_posted_after_as_of,
        coalesce(sum(memos.adjustment_usd) filter (where memos.is_posted_after_as_of), 0)
                                                                          as adjustment_usd_posted_after_as_of
    from {{ ref('silver_stg_netsuite_billing_adjustments') }} as memos
    left join programs on programs.program_id = memos.program_id
    where memos.billing_month <= cast('{{ var("as_of_date") }}' as date)
    group by all
),

unioned as (
    select *, 0 as adjustment_memos_posted_after_as_of, cast(0 as decimal(18, 2)) as adjustment_usd_posted_after_as_of
    from case_rate_priced
    union all by name
    select *, 0 as adjustment_memos_posted_after_as_of, cast(0 as decimal(18, 2)) as adjustment_usd_posted_after_as_of
    from platform_fee
    union all by name
    select * from adjustments
)

select
    revenue_component || '|' || coalesce(fee_id, program_id) || '|' || strftime(revenue_month, '%Y-%m')
                                                              as revenue_line_id,
    revenue_component,
    fee_id,
    program_id,
    employer_id,
    employer_name,
    employer_id = 'UNATTRIBUTED'                              as is_unattributed,
    revenue_month,
    episode_count,
    memo_count,
    rate_usd,
    discount_rate,
    cast(gross_usd as decimal(18, 2))                         as gross_usd,
    cast(round(gross_usd * discount_rate, 2) as decimal(18, 2)) as discount_usd,
    cast(gross_usd - round(gross_usd * discount_rate, 2) as decimal(18, 2)) as net_revenue_usd,
    adjustment_memos_posted_after_as_of,
    cast(adjustment_usd_posted_after_as_of as decimal(18, 2)) as adjustment_usd_posted_after_as_of
from unioned
