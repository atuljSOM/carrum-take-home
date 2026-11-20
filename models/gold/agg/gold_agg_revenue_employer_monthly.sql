{{ config(alias='agg_revenue_employer_monthly') }}

-- Grain: one row per employer x month, through the as-of month. Rules and columns: see the model's yml.

with revenue as (
    select * from {{ ref('gold_fact_revenue_monthly') }}
),

employers as (
    select distinct employer_id, employer_name, is_unattributed from revenue
),

months as (
    select month_start, year_quarter from {{ ref('gold_dim_months') }} where is_on_or_before_as_of
),

totals as (
    select
        employer_id,
        revenue_month,
        sum(net_revenue_usd) filter (where revenue_component = 'CASE_RATE')    as case_revenue_usd,
        sum(net_revenue_usd) filter (where revenue_component = 'PLATFORM_FEE') as platform_fee_revenue_usd,
        sum(net_revenue_usd) filter (where revenue_component = 'ADJUSTMENT')   as adjustments_usd,
        sum(gross_usd)       filter (where revenue_component <> 'ADJUSTMENT')  as gross_revenue_usd,
        sum(discount_usd)                                                      as discount_usd,
        sum(episode_count)                                                     as completed_episodes,
        sum(adjustment_usd_posted_after_as_of)                                 as adjustments_posted_after_as_of_usd
    from revenue
    group by all
)

select
    employers.employer_id || '|' || strftime(months.month_start, '%Y-%m') as employer_month_id,
    employers.employer_id,
    employers.employer_name,
    employers.is_unattributed,
    months.month_start                                                     as revenue_month,
    months.year_quarter,
    coalesce(totals.completed_episodes, 0)                                 as completed_episodes,
    coalesce(totals.gross_revenue_usd, 0)                                  as gross_revenue_usd,
    coalesce(totals.discount_usd, 0)                                       as discount_usd,
    coalesce(totals.case_revenue_usd, 0)                                   as case_revenue_usd,
    coalesce(totals.platform_fee_revenue_usd, 0)                           as platform_fee_revenue_usd,
    coalesce(totals.adjustments_usd, 0)                                    as adjustments_usd,
    coalesce(totals.case_revenue_usd, 0)
      + coalesce(totals.platform_fee_revenue_usd, 0)
      + coalesce(totals.adjustments_usd, 0)                                as total_revenue_usd,
    coalesce(totals.adjustments_posted_after_as_of_usd, 0)                 as adjustments_posted_after_as_of_usd
from employers
cross join months
left join totals
       on totals.employer_id = employers.employer_id
      and totals.revenue_month = months.month_start
