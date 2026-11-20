{{ config(alias='agg_revenue_program_monthly') }}

-- Grain: one row per program x month, through the as-of month. Rules and columns: see the model's yml.

with revenue as (
    select
        revenue.*,
        coalesce(programs.program_id, 'UNATTRIBUTED')                     as program_key,
        coalesce(programs.program_name, 'Unattributed (no valid program)') as program_name,
        programs.service_line
    from {{ ref('gold_fact_revenue_monthly') }} as revenue
    left join {{ ref('gold_dim_programs') }} as programs
        on programs.program_id = revenue.program_id
),

program_keys as (
    select distinct program_key, program_name, service_line, employer_id, employer_name, is_unattributed
    from revenue
),

months as (
    select month_start, year_quarter from {{ ref('gold_dim_months') }} where is_on_or_before_as_of
),

totals as (
    select
        program_key,
        revenue_month,
        sum(net_revenue_usd) filter (where revenue_component = 'CASE_RATE')    as case_revenue_usd,
        sum(net_revenue_usd) filter (where revenue_component = 'PLATFORM_FEE') as platform_fee_revenue_usd,
        sum(net_revenue_usd) filter (where revenue_component = 'ADJUSTMENT')   as adjustments_usd,
        sum(gross_usd)       filter (where revenue_component <> 'ADJUSTMENT')  as gross_revenue_usd,
        sum(discount_usd)                                                      as discount_usd,
        sum(episode_count)                                                     as completed_episodes,
        sum(adjustments_savings_guarantee_usd)                       as adjustments_savings_guarantee_usd,
        sum(adjustments_performance_guarantee_usd)                   as adjustments_performance_guarantee_usd,
        sum(adjustments_goodwill_usd)                                as adjustments_goodwill_usd,
        sum(adjustments_invoice_correction_usd)                      as adjustments_invoice_correction_usd,
        sum(adjustments_other_usd)                                   as adjustments_other_usd,
        sum(adjustment_usd_posted_after_as_of)                                 as adjustments_posted_after_as_of_usd
    from revenue
    group by all
)

select
    program_keys.program_key || '|' || strftime(months.month_start, '%Y-%m') as program_month_id,
    program_keys.program_key                                                as program_id,
    program_keys.program_name,
    program_keys.service_line,
    program_keys.employer_id,
    program_keys.employer_name,
    program_keys.is_unattributed,
    months.month_start                                                      as revenue_month,
    months.year_quarter,
    coalesce(totals.completed_episodes, 0)                                  as completed_episodes,
    coalesce(totals.gross_revenue_usd, 0)                                   as gross_revenue_usd,
    coalesce(totals.discount_usd, 0)                                        as discount_usd,
    coalesce(totals.case_revenue_usd, 0)                                    as case_revenue_usd,
    coalesce(totals.platform_fee_revenue_usd, 0)                            as platform_fee_revenue_usd,
    coalesce(totals.adjustments_usd, 0)                                     as adjustments_usd,
    coalesce(totals.adjustments_savings_guarantee_usd, 0)               as adjustments_savings_guarantee_usd,
    coalesce(totals.adjustments_performance_guarantee_usd, 0)           as adjustments_performance_guarantee_usd,
    coalesce(totals.adjustments_goodwill_usd, 0)                        as adjustments_goodwill_usd,
    coalesce(totals.adjustments_invoice_correction_usd, 0)              as adjustments_invoice_correction_usd,
    coalesce(totals.adjustments_other_usd, 0)                           as adjustments_other_usd,
    coalesce(totals.case_revenue_usd, 0)
      + coalesce(totals.platform_fee_revenue_usd, 0)
      + coalesce(totals.adjustments_usd, 0)                                 as total_revenue_usd,
    coalesce(totals.adjustments_posted_after_as_of_usd, 0)                  as adjustments_posted_after_as_of_usd
from program_keys
cross join months
left join totals
       on totals.program_key = program_keys.program_key
      and totals.revenue_month = months.month_start
