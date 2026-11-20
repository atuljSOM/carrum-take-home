{{ config(alias='agg_revenue_employer_monthly') }}

-- Grain: one row per employer x month, through the as-of month. A pure roll-up of
-- gold_agg_revenue_program_monthly. Rules and columns: see the model's yml.

select
    employer_id || '|' || strftime(revenue_month, '%Y-%m') as employer_month_id,
    employer_id,
    employer_name,
    is_unattributed,
    revenue_month,
    year_quarter,
    sum(completed_episodes)                 as completed_episodes,
    sum(gross_revenue_usd)                  as gross_revenue_usd,
    sum(discount_usd)                       as discount_usd,
    sum(case_revenue_usd)                   as case_revenue_usd,
    sum(platform_fee_revenue_usd)           as platform_fee_revenue_usd,
    sum(adjustments_usd)                    as adjustments_usd,
    sum(total_revenue_usd)                  as total_revenue_usd,
    sum(adjustments_posted_after_as_of_usd) as adjustments_posted_after_as_of_usd
from {{ ref('gold_agg_revenue_program_monthly') }}
group by all
