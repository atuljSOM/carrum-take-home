-- Reconciliation: case-rate revenue in gold_fact_revenue_monthly equals an independent recompute
-- from the episode fact and the fee lines (eligible episodes x rate x (1 - discount), by fee line
-- and surgery month, up to the as-of month). Catches episodes dropped or double-counted between
-- the two facts, a wrong join, or a discount applied twice. Severity: error.
-- Returns one row per fee line x month where the episode count or net revenue differs.

with expected as (
    select
        episodes.fee_id,
        episodes.surgery_month                                              as revenue_month,
        count(*)                                                            as episode_count,
        sum(fee_lines.rate_usd)
          - round(sum(fee_lines.rate_usd) * any_value(fee_lines.discount_rate), 2) as net_revenue_usd
    from {{ ref('gold_fact_episodes') }} as episodes
    join {{ ref('gold_dim_fee_lines') }} as fee_lines on fee_lines.fee_id = episodes.fee_id
    where episodes.is_revenue_eligible
      and episodes.surgery_month <= cast('{{ var("as_of_date") }}' as date)
    group by all
),

actual as (
    select fee_id, revenue_month, episode_count, net_revenue_usd
    from {{ ref('gold_fact_revenue_monthly') }}
    where revenue_component = 'CASE_RATE'
)

select
    coalesce(expected.fee_id, actual.fee_id)               as fee_id,
    coalesce(expected.revenue_month, actual.revenue_month) as revenue_month,
    expected.episode_count                                 as expected_episodes,
    actual.episode_count                                   as actual_episodes,
    expected.net_revenue_usd                               as expected_net_usd,
    actual.net_revenue_usd                                 as actual_net_usd
from expected
full outer join actual
  on actual.fee_id = expected.fee_id
 and actual.revenue_month = expected.revenue_month
where expected.episode_count is distinct from actual.episode_count
   or expected.net_revenue_usd is distinct from actual.net_revenue_usd
