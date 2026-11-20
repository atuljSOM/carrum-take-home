-- Part 2a: recognized revenue by employer and month for Q2 2026 (April, May, June).
--
-- One row per employer per month, then one Q2 total row per employer, then one grand total.
-- Employers are rolled up to the ultimate parent account (one employer = one line); revenue with
-- no valid program appears as "Unattributed (no valid program)". Components are net of discount;
-- adjustments are added after discount. All business rules live in the gold models; this query
-- only filters and totals gold_agg_revenue_employer_monthly.

with q2 as (
    select *
    from {{ ref('gold_agg_revenue_employer_monthly') }}
    where year_quarter = '2026-Q2'
),

rolled as (
    select
        employer_name,
        is_unattributed,
        strftime(revenue_month, '%Y-%m')         as revenue_month,
        grouping(employer_name)                  as is_grand_total,
        grouping(revenue_month)                  as is_quarter_total,
        sum(completed_episodes)                  as completed_episodes,
        sum(case_revenue_usd)                    as case_revenue_usd,
        sum(platform_fee_revenue_usd)            as platform_fee_revenue_usd,
        sum(adjustments_usd)                     as adjustments_usd,
        sum(total_revenue_usd)                   as total_revenue_usd,
        sum(adjustments_posted_after_as_of_usd)  as adjustments_posted_after_as_of_usd
    from q2
    group by grouping sets (
        (employer_name, is_unattributed, revenue_month),
        (employer_name, is_unattributed),
        ()
    )
)

select
    case when is_grand_total = 1 then 'All employers' else employer_name end as employer,
    case when is_quarter_total = 1 then '2026-Q2 total' else revenue_month end as period,
    completed_episodes,
    case_revenue_usd,
    platform_fee_revenue_usd,
    adjustments_usd,
    total_revenue_usd,
    adjustments_posted_after_as_of_usd
from rolled
order by
    is_grand_total,
    is_unattributed,
    employer_name,
    is_quarter_total,
    revenue_month
