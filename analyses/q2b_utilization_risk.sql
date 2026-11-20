-- Part 2b: case-rate fee lines pacing behind projection as of 2026-06-30, worst first.
-- Pacing and revenue at risk are defined in gold_agg_pacing_fee_line. The escalation call is a
-- judgement, so it lives here:
--   escalate: ratio < 0.75, revenue at risk >= $40k, >= 60 days elapsed, has an employer, and the
--             program was live for the whole window (no go-live gap)
--   watch:    any other line with ratio < 0.75

select
    fee_id,
    employer_name,
    program_name,
    completed_episodes,
    round(expected_episodes, 1)                    as expected_episodes,
    round(pacing_ratio, 2)                         as pacing_ratio,
    revenue_at_risk_usd,
    case
        when pacing_ratio >= 0.75                  then null
        when not is_unattributed
         and revenue_at_risk_usd >= 40000
         and elapsed_days >= 60
         and not coalesce(is_go_live_after_window_start, false) then 'escalate'
        else 'watch'
    end                                            as client_success_action,
    concat_ws('; ',
        case when is_window_closed then 'window closed: ratio is final' end,
        case when is_go_live_after_window_start then 'program went live ' || go_live_date || ' after the window started' end,
        case when elapsed_days < 60 then 'only ' || elapsed_days || ' days elapsed' end,
        case when is_unattributed then 'no program or employer' end
    )                                              as notes
from {{ ref('gold_agg_pacing_fee_line') }}
where pacing_ratio < 1
order by pacing_ratio
