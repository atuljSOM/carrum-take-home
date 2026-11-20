-- Part 2b: case-rate fee lines pacing behind projection as of 2026-06-30, worst first.
-- Pacing, revenue at risk and the escalate / watch rule are defined in gold_agg_pacing_fee_line.

select
    fee_id,
    employer_name,
    program_name,
    completed_episodes,
    round(expected_episodes, 1)                    as expected_episodes,
    round(pacing_ratio, 2)                         as pacing_ratio,
    revenue_at_risk_usd,
    client_success_action,
    concat_ws('; ',
        case when is_window_closed then 'window closed: ratio is final' end,
        case when is_go_live_after_window_start then 'program went live ' || go_live_date || ' after the window started' end,
        case when elapsed_days < 60 then 'only ' || elapsed_days || ' days elapsed' end,
        case when is_unattributed then 'no program or employer' end
    )                                              as notes
from {{ ref('gold_agg_pacing_fee_line') }}
where pacing_ratio < 1
order by pacing_ratio
