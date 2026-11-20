-- Reconciliation: the employer x month aggregate (the CFO view, Part 2a) loses and adds nothing.
-- For every employer and month, each component in gold_agg_revenue_employer_monthly equals the
-- sum of the matching rows in gold_fact_revenue_monthly, and total = case + platform + adjustments.
-- Catches a roll-up that drops an employer, a fan-out join, or a component mapped to the wrong
-- column. Severity: error. Returns one row per employer x month that does not tie.

with fact as (
    select
        employer_id,
        revenue_month,
        coalesce(sum(net_revenue_usd) filter (where revenue_component = 'CASE_RATE'), 0)    as case_usd,
        coalesce(sum(net_revenue_usd) filter (where revenue_component = 'PLATFORM_FEE'), 0) as platform_usd,
        coalesce(sum(net_revenue_usd) filter (where revenue_component = 'ADJUSTMENT'), 0)   as adjustments_usd,
        coalesce(sum(net_revenue_usd), 0)                                                   as total_usd
    from {{ ref('gold_fact_revenue_monthly') }}
    group by all
),

agg as (
    select employer_id, revenue_month, case_revenue_usd, platform_fee_revenue_usd,
           adjustments_usd, total_revenue_usd
    from {{ ref('gold_agg_revenue_employer_monthly') }}
)

select
    coalesce(agg.employer_id, fact.employer_id)       as employer_id,
    coalesce(agg.revenue_month, fact.revenue_month)   as revenue_month,
    fact.total_usd                                    as fact_total_usd,
    agg.total_revenue_usd                             as agg_total_usd
from agg
full outer join fact
  on fact.employer_id = agg.employer_id
 and fact.revenue_month = agg.revenue_month
where agg.employer_id is null                                         -- fact revenue missing from the agg
   or coalesce(fact.case_usd, 0)        <> agg.case_revenue_usd
   or coalesce(fact.platform_usd, 0)    <> agg.platform_fee_revenue_usd
   or coalesce(fact.adjustments_usd, 0) <> agg.adjustments_usd
   or agg.total_revenue_usd <> agg.case_revenue_usd + agg.platform_fee_revenue_usd + agg.adjustments_usd
