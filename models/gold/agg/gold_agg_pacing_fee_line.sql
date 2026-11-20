{{ config(alias='agg_pacing_fee_line') }}

-- Grain: one row per case-rate fee line, as of var('as_of_date'). Rules and columns: see the model's yml.

with fee_lines as (
    select * from {{ ref('gold_dim_fee_lines') }} where fee_type = 'CASE_RATE'
),

programs as (
    select program_id, go_live_date from {{ ref('gold_dim_programs') }}
),

completed as (
    select fee_id, count(*) as completed_episodes
    from {{ ref('gold_fact_episodes') }}
    where is_revenue_eligible
    group by fee_id
),

windowed as (
    select
        fee_lines.*,
        programs.go_live_date,
        coalesce(completed.completed_episodes, 0)                                as completed_episodes,
        datediff('day', fee_lines.effective_start, fee_lines.effective_end) + 1  as window_days,
        least(greatest(
            datediff('day', fee_lines.effective_start, cast('{{ var("as_of_date") }}' as date)) + 1, 0),
            datediff('day', fee_lines.effective_start, fee_lines.effective_end) + 1) as elapsed_days
    from fee_lines
    left join programs  on programs.program_id = fee_lines.program_id
    left join completed on completed.fee_id = fee_lines.fee_id
)

select
    fee_id,
    program_id,
    program_name,
    employer_id,
    employer_name,
    employer_id = 'UNATTRIBUTED'                                          as is_unattributed,
    effective_start,
    effective_end,
    go_live_date,
    window_days,
    elapsed_days,
    elapsed_days / window_days                                            as elapsed_share,
    projected_episodes,
    projected_episodes * elapsed_days / window_days                       as expected_episodes,
    completed_episodes,
    greatest(projected_episodes * elapsed_days / window_days - completed_episodes, 0)
                                                                          as shortfall_episodes,
    completed_episodes / nullif(projected_episodes * elapsed_days / window_days, 0)
                                                                          as pacing_ratio,
    rate_usd,
    discount_rate,
    cast(round(greatest(projected_episodes * elapsed_days / window_days - completed_episodes, 0)
               * rate_usd * (1 - discount_rate), 2) as decimal(18, 2))    as revenue_at_risk_usd,
    elapsed_days = window_days                                            as is_window_closed,
    go_live_date > effective_start                                        as is_go_live_after_window_start
from windowed
