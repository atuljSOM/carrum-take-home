-- Reconciliation: the revenue aggregates lose and add nothing.
--   1. gold_agg_revenue_program_monthly: each component per program x month equals the matching
--      gold_fact_revenue_monthly rows, total = case + platform + adjustments, and the adjustment
--      reason columns sum to adjustments.
--   2. gold_agg_revenue_employer_monthly (the CFO view, Part 2a): each employer x month equals the
--      sum of its programs.
-- Catches a dropped or duplicated program, a fan-out join, a component in the wrong column, or a
-- roll-up that drifts. Severity: error. Returns one row per program or employer month that does not tie.

with fact as (
    select
        coalesce(programs.program_id, 'UNATTRIBUTED')                                       as program_id,
        revenue.revenue_month,
        coalesce(sum(net_revenue_usd) filter (where revenue_component = 'CASE_RATE'), 0)    as case_usd,
        coalesce(sum(net_revenue_usd) filter (where revenue_component = 'PLATFORM_FEE'), 0) as platform_usd,
        coalesce(sum(net_revenue_usd) filter (where revenue_component = 'ADJUSTMENT'), 0)   as adjustments_usd
    from {{ ref('gold_fact_revenue_monthly') }} as revenue
    left join {{ ref('gold_dim_programs') }} as programs on programs.program_id = revenue.program_id
    group by all
),

program_agg as (
    select * from {{ ref('gold_agg_revenue_program_monthly') }}
),

program_check as (
    select 'program' as level, coalesce(program_agg.program_id, fact.program_id) as id,
           coalesce(program_agg.revenue_month, fact.revenue_month) as revenue_month
    from program_agg
    full outer join fact
      on fact.program_id = program_agg.program_id
     and fact.revenue_month = program_agg.revenue_month
    where program_agg.program_id is null
       or coalesce(fact.case_usd, 0)        <> program_agg.case_revenue_usd
       or coalesce(fact.platform_usd, 0)    <> program_agg.platform_fee_revenue_usd
       or coalesce(fact.adjustments_usd, 0) <> program_agg.adjustments_usd
       or program_agg.total_revenue_usd
          <> program_agg.case_revenue_usd + program_agg.platform_fee_revenue_usd + program_agg.adjustments_usd
       or program_agg.adjustments_usd
          <> program_agg.adjustments_savings_guarantee_usd + program_agg.adjustments_performance_guarantee_usd
           + program_agg.adjustments_goodwill_usd + program_agg.adjustments_invoice_correction_usd
           + program_agg.adjustments_other_usd
),

employer_from_programs as (
    select employer_id, revenue_month,
           sum(case_revenue_usd) as case_usd, sum(platform_fee_revenue_usd) as platform_usd,
           sum(adjustments_usd) as adjustments_usd, sum(total_revenue_usd) as total_usd
    from program_agg
    group by all
),

employer_check as (
    select 'employer' as level, coalesce(e.employer_id, p.employer_id) as id,
           coalesce(e.revenue_month, p.revenue_month) as revenue_month
    from {{ ref('gold_agg_revenue_employer_monthly') }} as e
    full outer join employer_from_programs as p
      on p.employer_id = e.employer_id
     and p.revenue_month = e.revenue_month
    where e.employer_id is null or p.employer_id is null
       or e.case_revenue_usd <> p.case_usd
       or e.platform_fee_revenue_usd <> p.platform_usd
       or e.adjustments_usd <> p.adjustments_usd
       or e.total_revenue_usd <> p.total_usd
)

select * from program_check
union all
select * from employer_check
