-- Reconciliation: every distinct NetSuite memo with a billing month on or before the as-of month
-- reaches revenue exactly once, orphans and late-posted memos included (both are documented as
-- included). Compares memo count and amount by billing month between silver and the revenue fact.
-- Catches a memo dropped by a join or a filter, or double-counted. Severity: error.
-- Returns one row per billing month that does not tie.

with memos as (
    select
        billing_month,
        count(*)            as memo_count,
        sum(adjustment_usd) as adjustment_usd
    from {{ ref('silver_stg_netsuite_billing_adjustments') }}
    where billing_month <= cast('{{ var("as_of_date") }}' as date)
    group by all
),

revenue as (
    select
        revenue_month       as billing_month,
        sum(memo_count)     as memo_count,
        sum(net_revenue_usd) as adjustment_usd
    from {{ ref('gold_fact_revenue_monthly') }}
    where revenue_component = 'ADJUSTMENT'
    group by all
)

select
    coalesce(memos.billing_month, revenue.billing_month) as billing_month,
    memos.memo_count                                     as silver_memos,
    revenue.memo_count                                   as revenue_memos,
    memos.adjustment_usd                                 as silver_usd,
    revenue.adjustment_usd                               as revenue_usd
from memos
full outer join revenue on revenue.billing_month = memos.billing_month
where memos.memo_count is distinct from revenue.memo_count
   or memos.adjustment_usd is distinct from revenue.adjustment_usd
