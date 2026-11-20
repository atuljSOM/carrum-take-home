-- Part 2c: data quality register. All logic and magnitudes live in gold_rpt_data_quality_register;
-- ordered by the size of the effect on Q2 revenue.

select *
from {{ ref('gold_rpt_data_quality_register') }}
order by abs(coalesce(q2_revenue_impact_usd, 0)) + abs(coalesce(q2_revenue_misattributed_usd, 0)) desc, issue_id
