-- Business rule: after the discount rule (blank = 0, above 1 = whole percent), every fee line's
-- discount_rate is a fraction from 0 up to, but not including, 1. A value outside that range
-- means a new discount_pct entry the rule does not cover (e.g. 120 or a negative number) and
-- would produce negative or inflated revenue. Severity: error.
-- Returns the offending fee lines.

select fee_id, discount_pct_raw, discount_rate, discount_rule_applied
from {{ ref('gold_dim_fee_lines') }}
where discount_rate is null
   or discount_rate < 0
   or discount_rate >= 1
