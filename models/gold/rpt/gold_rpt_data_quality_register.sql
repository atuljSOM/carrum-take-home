{{ config(alias='rpt_data_quality_register') }}

-- Grain: one row per data-quality issue. Rules and columns: see the model's yml.
-- Every count and dollar amount is computed here from silver and gold; only the descriptive text
-- is written by hand. Impact = (naive handling described in impact_basis) - (as modelled).

with params as (
    select
        cast('{{ var("as_of_date") }}' as date)                                as as_of_date,
        cast(date_trunc('quarter', cast('{{ var("as_of_date") }}' as date)) as date) as q_start,
        cast(date_trunc('month', cast('{{ var("as_of_date") }}' as date)) as date)   as q_last_month
),

fee as (
    select *, rate_usd * (1 - discount_rate) as net_rate
    from {{ ref('gold_dim_fee_lines') }}
),

ep as (
    select
        e.*,
        fee.net_rate,
        fee.discount_rate,
        coalesce(e.surgery_month between p.q_start and p.q_last_month, false) as in_q,
        -- would earn the case rate if its current status were COMPLETED (mirrors the exclusions)
        not e.is_test_record and e.fee_type = 'CASE_RATE' and e.surgery_month is not null
            and not coalesce(e.is_surgery_outside_fee_window, false)         as is_priceable
    from {{ ref('gold_fact_episodes') }} as e
    left join fee on fee.fee_id = e.fee_id
    cross join params as p
),

rec as (
    select * from {{ ref('silver_stg_care_platform_episodes') }}
),

memo as (
    select
        m.*,
        m.billing_month between p.q_start and p.q_last_month as in_q,
        prg.program_id is not null                                  as has_program,
        -- named in the detail so a caveat can be tied to the employer in a question
        coalesce(prg.employer_name, 'Unattributed')                 as employer_name
    from {{ ref('silver_stg_netsuite_billing_adjustments') }} as m
    left join {{ ref('gold_dim_programs') }} as prg on prg.program_id = m.program_id
    cross join params as p
),

rev as (
    select r.*, r.revenue_month between p.q_start and p.q_last_month as in_q
    from {{ ref('gold_fact_revenue_monthly') }} as r
    cross join params as p
),

pacing as (
    select * from {{ ref('gold_agg_pacing_fee_line') }}
),

-- latest record in the whole extract, priced with the same exclusions (for DQ-03)
latest_in_extract as (
    select
        r.episode_id,
        r.episode_status = 'COMPLETED'
            and not r.is_test_record
            and fee.fee_type = 'CASE_RATE'
            and case
                    when r.surgery_date is not null
                        then r.surgery_date between fee.effective_start and fee.effective_end
                    else r.invoice_month <= fee.effective_end and last_day(r.invoice_month) >= fee.effective_start
                end                                                             as is_eligible,
        fee.net_rate,
        coalesce(cast(date_trunc('month', r.surgery_date) as date), r.invoice_month)
            between p.q_start and p.q_last_month                                as in_q
    from rec as r
    left join fee on fee.fee_id = r.fee_id
    cross join params as p
    qualify row_number() over (partition by r.episode_id order by r.record_updated_at desc) = 1
),

metrics as (
    -- DQ-01 exact duplicate episode records
    select 'DQ-01' as issue_id,
        (select sum(source_row_count - 1) from rec)                                     as rows_affected,
        (select coalesce(sum((r.source_row_count - 1) * ep.net_rate), 0)
           from ep join rec as r on r.episode_id = ep.episode_id and r.record_updated_at = ep.current_status_at
          where ep.is_revenue_eligible and ep.in_q)                                       as q2_revenue_impact_usd,
        null::decimal(18, 2)                                                              as q2_revenue_misattributed_usd,
        (select coalesce(sum(r.source_row_count - 1), 0)
           from ep join rec as r on r.episode_id = ep.episode_id and r.record_updated_at = ep.current_status_at
          where ep.is_revenue_eligible)                                                   as pacing_completed_impact,
        null::varchar                                                                     as detail

    -- DQ-02 status log: completions later reversed (on or before the as-of date)
    union all select 'DQ-02',
        (select count(distinct ep.episode_id) from ep join rec as r using (episode_id)
          where r.episode_status = 'COMPLETED' and not r.is_recorded_after_as_of and ep.current_status <> 'COMPLETED'),
        (select coalesce(sum(net_rate), 0) from ep
          where in_q and is_priceable and current_status <> 'COMPLETED'
            and episode_id in (select episode_id from rec where episode_status = 'COMPLETED' and not is_recorded_after_as_of)),
        null,
        (select count(*) from ep
          where is_priceable and current_status <> 'COMPLETED'
            and episode_id in (select episode_id from rec where episode_status = 'COMPLETED' and not is_recorded_after_as_of)),
        null

    -- DQ-03 records dated after the extract / as-of date
    union all select 'DQ-03',
        (select count(*) from rec where is_recorded_after_as_of),
        (select coalesce(sum(net_rate) filter (where is_eligible and in_q), 0) from latest_in_extract)
          - (select coalesce(sum(net_rate), 0) from ep where is_revenue_eligible and in_q),
        null,
        (select count(*) filter (where is_eligible) from latest_in_extract)
          - (select count(*) from ep where is_revenue_eligible),
        (select count(*) || ' status changes, ' from ep where is_status_changed_after_as_of)
          || (select count(distinct episode_id) from rec
               where episode_id not in (select episode_id from ep)) || ' episodes seen only after the as-of date'

    -- DQ-04 surgery dates in MM/DD/YYYY
    union all select 'DQ-04',
        (select count(*) from rec where surgery_date_source_format = 'MM/DD/YYYY'),
        (select -coalesce(sum(net_rate), 0) from ep where is_revenue_eligible and in_q and surgery_date_source_format = 'MM/DD/YYYY'),
        null,
        (select -count(*) from ep where is_revenue_eligible and surgery_date_source_format = 'MM/DD/YYYY'),
        null

    -- DQ-05 completed episodes with no surgery date
    union all select 'DQ-05',
        (select count(*) from ep where surgery_date is null and current_status = 'COMPLETED'),
        (select -coalesce(sum(net_rate), 0) from ep where is_revenue_eligible and in_q and surgery_month_source = 'invoice_month_fallback'),
        null,
        (select -count(*) from ep where is_revenue_eligible and surgery_month_source = 'invoice_month_fallback'),
        null

    -- DQ-06 test records on a fee line not in the schedule
    union all select 'DQ-06',
        (select count(*) from rec where is_test_record),
        0, null, 0,
        (select count(*) || ' completed test episodes would inflate episode counts; their fee line has no rate'
           from ep where is_test_record and current_status = 'COMPLETED')

    -- DQ-07 episodes billed to a platform-fee line
    union all select 'DQ-07',
        (select count(*) from ep where fee_type = 'PLATFORM_FEE' and current_status = 'COMPLETED'),
        (select coalesce(sum(net_rate), 0) from ep where fee_type = 'PLATFORM_FEE' and current_status = 'COMPLETED' and in_q),
        null, 0, null

    -- DQ-08 completed before the fee line's effective window
    union all select 'DQ-08',
        (select count(*) from ep where revenue_exclusion_reason = 'surgery outside fee line window'),
        (select coalesce(sum(net_rate), 0) from ep where revenue_exclusion_reason = 'surgery outside fee line window' and in_q),
        null,
        (select count(*) from ep where revenue_exclusion_reason = 'surgery outside fee line window'),
        (select string_agg(fee_id || ' pacing ' || round(pacing_ratio, 2) || ' -> '
                || round((completed_episodes + n) / expected_episodes, 2), '; ' order by fee_id)
           from pacing join (select fee_id, count(*) as n from ep
                              where revenue_exclusion_reason = 'surgery outside fee line window' group by 1) using (fee_id))

    -- DQ-09 discount_pct entered as a whole percent
    union all select 'DQ-09',
        (select count(*) from fee where discount_pct_raw > 1),
        (select coalesce(sum(rev.gross_usd * (fee.discount_rate - fee.discount_pct_raw)), 0)
           from rev join fee using (fee_id) where rev.in_q and fee.discount_pct_raw > 1),
        null, 0,
        (select string_agg(fee_id || ' entered ' || discount_pct_raw, '; ' order by fee_id) from fee where discount_pct_raw > 1)

    -- DQ-10 discount_pct blank
    union all select 'DQ-10',
        (select count(*) from fee where discount_pct_raw is null),
        (select -coalesce(sum(rev.net_revenue_usd), 0) from rev join fee using (fee_id)
          where rev.in_q and fee.discount_pct_raw is null),
        null, 0, null

    -- DQ-11 discount on a platform-fee line
    union all select 'DQ-11',
        (select count(*) from fee where fee_type = 'PLATFORM_FEE' and discount_rate > 0),
        (select coalesce(sum(rev.discount_usd), 0) from rev join fee using (fee_id)
          where rev.in_q and fee.fee_type = 'PLATFORM_FEE' and fee.discount_rate > 0),
        null, 0, null

    -- DQ-12 fee lines with no program
    union all select 'DQ-12',
        (select count(*) from fee where is_orphan),
        (select -coalesce(sum(rev.net_revenue_usd), 0) from rev join fee using (fee_id) where rev.in_q and fee.is_orphan),
        null, 0,
        (select string_agg(fee_id, ', ' order by fee_id) from fee where is_orphan)

    -- DQ-13 account hierarchy: duplicate account, union, missing parent
    union all select 'DQ-13',
        (select count(*) from {{ ref('gold_dim_employers') }} where account_id <> employer_id or is_parent_missing),
        0,
        (select coalesce(sum(rev.net_revenue_usd), 0)
           from rev join {{ ref('gold_dim_programs') }} as prg using (program_id)
          where rev.in_q and prg.account_id <> prg.employer_id),
        0,
        (select string_agg(account_id || ' -> ' || employer_id || case when is_parent_missing then ' (parent missing)' else '' end, '; ' order by account_id)
           from {{ ref('gold_dim_employers') }} where account_id <> employer_id or is_parent_missing)

    -- DQ-14 program went live after its fee lines started
    union all select 'DQ-14',
        (select count(*) from pacing where is_go_live_after_window_start),
        (select -coalesce(sum(rev.net_revenue_usd), 0)
           from rev join {{ ref('gold_dim_programs') }} as prg using (program_id)
          where rev.in_q and rev.revenue_component = 'PLATFORM_FEE'
            and rev.revenue_month < date_trunc('month', prg.go_live_date)),
        null, 0,
        (select string_agg(fee_id || ' pacing ' || round(pacing_ratio, 2) || ' -> '
                || round(completed_episodes / (projected_episodes
                     * (datediff('day', go_live_date, p.as_of_date) + 1)
                     / (datediff('day', go_live_date, effective_end) + 1)), 2)
                || ' if pro-rated from go-live ' || go_live_date, '; ' order by fee_id)
           from pacing cross join params as p where is_go_live_after_window_start)

    -- DQ-15 duplicate NetSuite memo
    union all select 'DQ-15',
        (select sum(source_row_count - 1) from memo),
        (select coalesce(sum(adjustment_usd * (source_row_count - 1)), 0) from memo where in_q),
        null, 0,
        (select string_agg(memo_id || ' (' || employer_name || ')', ', ' order by memo_id) from memo where source_row_count > 1)

    -- DQ-16 billing_month not in YYYY-MM
    union all select 'DQ-16',
        (select count(*) from memo where billing_month_source_format <> 'YYYY-MM'),
        (select -coalesce(sum(adjustment_usd), 0) from memo where in_q and billing_month_source_format <> 'YYYY-MM'),
        null, 0,
        (select string_agg(memo_id || ' (' || billing_month_source_format || ', ' || employer_name || ')', ', ' order by memo_id) from memo where billing_month_source_format <> 'YYYY-MM')

    -- DQ-17 memo on a program not in Salesforce
    union all select 'DQ-17',
        (select count(*) from memo where not has_program),
        (select -coalesce(sum(adjustment_usd), 0) from memo where in_q and not has_program),
        null, 0,
        (select string_agg(memo_id || ' on ' || program_id, ', ' order by memo_id) from memo where not has_program)

    -- DQ-18 memos posted after the as-of date
    union all select 'DQ-18',
        (select count(*) from memo where is_posted_after_as_of),
        (select -coalesce(sum(adjustment_usd), 0) from memo where in_q and is_posted_after_as_of),
        null, 0,
        (select string_agg(memo_id || ' ' || adjustment_usd || ' (' || employer_name || ')', ', ' order by memo_id) from memo where is_posted_after_as_of)

    -- DQ-19 outlier memo (over 5x the median absolute amount)
    union all select 'DQ-19',
        (select count(*) from memo where abs(adjustment_usd) > 5 * (select median(abs(adjustment_usd)) from memo)),
        (select -coalesce(sum(adjustment_usd), 0) from memo
          where in_q and abs(adjustment_usd) > 5 * (select median(abs(adjustment_usd)) from memo)),
        null, 0,
        (select string_agg(memo_id || ' ' || adjustment_usd || ' (' || employer_name || ', ' || reason || ')', ', ' order by memo_id) from memo
          where abs(adjustment_usd) > 5 * (select median(abs(adjustment_usd)) from memo))

    -- DQ-20 "credit" memos with a positive amount
    union all select 'DQ-20',
        (select count(*) from memo where reason like '%credit%' and adjustment_usd > 0),
        (select -2 * coalesce(sum(adjustment_usd), 0) from memo where in_q and reason like '%credit%' and adjustment_usd > 0),
        null, 0,
        (select string_agg(memo_id || ' +' || adjustment_usd || ' (' || employer_name || ')', ', ' order by memo_id) from memo where reason like '%credit%' and adjustment_usd > 0)

    -- DQ-21 invoice_month lags the surgery month
    union all select 'DQ-21',
        (select count(*) from ep where is_revenue_eligible and surgery_month_source = 'surgery_date'
            and invoice_month <> surgery_month),
        (select coalesce(sum(net_rate) filter (where invoice_month between p.q_start and p.q_last_month), 0)
              - coalesce(sum(net_rate) filter (where in_q), 0)
           from ep cross join params as p where is_revenue_eligible),
        null, 0, null

    -- DQ-22 SCHEDULED episodes whose surgery date has passed
    union all select 'DQ-22',
        (select count(*) from ep cross join params as p where current_status = 'SCHEDULED' and surgery_date <= p.as_of_date),
        null, null, null,
        (select 'up to $' || printf('%.2f', coalesce(sum(net_rate) filter (where in_q and is_priceable), 0))
                || ' Q2 revenue and ' || count(*) filter (where is_priceable) || ' completed episodes if these were actually completed; '
                || count(*) filter (where latest_status_in_extract = 'COMPLETED') || ' of them are COMPLETED in records after the as-of date'
           from ep cross join params as p where current_status = 'SCHEDULED' and surgery_date <= p.as_of_date)
),

catalog (issue_id, source_file, issue, detection, handling, caught_by_test, fix_belongs, impact_basis) as (
    values
    ('DQ-01', 'care_platform_episodes', 'Exact duplicate status records',
     'Rows identical in every column', 'Fixed in silver: collapsed, copies counted in source_row_count',
     'no_exact_duplicate_rows (bronze, warn); ut_stg_episodes_exact_duplicates_collapsed', 'Upstream (extract) and model',
     'Revenue and completions if each copy of a current COMPLETED record were counted'),
    ('DQ-02', 'care_platform_episodes', 'Completions later reversed in the status log',
     'Episode has a COMPLETED record but a later non-completed record on or before the as-of date', 'Fixed in gold: current status = latest record',
     'ut_fact_episodes_current_status_is_latest_record', 'Model (the log is correct by design)',
     'Revenue and completions if every COMPLETED record counted, not the current status'),
    ('DQ-03', 'care_platform_episodes', 'Records dated after the 2026-06-30 extract date',
     'record_updated_at after the as-of date (up to 2026-08-16)', 'Excluded from current status; summarized in later_* columns',
     'ut_stg_episodes_recorded_after_as_of_boundary; ut_fact_episodes_records_after_as_of_ignored', 'Upstream (extract date or timestamps are wrong)',
     'Revenue and completions if the latest record in the whole extract were used'),
    ('DQ-04', 'care_platform_episodes', 'Surgery dates in MM/DD/YYYY',
     'Value fails an ISO date cast but matches MM/DD/YYYY', 'Fixed in silver: parsed month first',
     'castable_to surgery_date (bronze, warn); ut_stg_episodes_surgery_date_both_formats', 'Upstream (one date format) and model',
     'Revenue and completions lost if these dates were left unparsed and the episodes dropped'),
    ('DQ-05', 'care_platform_episodes', 'Completed episodes with no surgery date',
     'surgery_date null', 'Fixed in gold: reported in invoice_month, flagged in surgery_month_source',
     'not_null surgery_date (bronze, warn); ut_fact_episodes_missing_surgery_date_falls_back_to_invoice_month', 'Upstream (required field)',
     'Revenue and completions lost if these episodes were excluded'),
    ('DQ-06', 'care_platform_episodes', 'Test records (provider PRV-TEST, member TEST-*) on fee line FEE-999, which is not in the schedule',
     'Provider and member ID patterns; fee_id not in the fee schedule', 'Excluded and flagged',
     'relationships episodes.fee_id (silver, warn); ut_stg_episodes_test_record_flag', 'Upstream (test data in a production extract)',
     'No revenue effect (no rate); see detail for episode counts'),
    ('DQ-07', 'care_platform_episodes', 'Completed episodes billed to a platform-fee line (FEE-403)',
     'Episode fee_id resolves to fee_type PLATFORM_FEE', 'Excluded and flagged; not remapped',
     'ut_fact_episodes_revenue_exclusion_reasons', 'Upstream (billing assignment)',
     'Revenue if these episodes were priced at the platform line''s rate'),
    ('DQ-08', 'care_platform_episodes', 'Completed episodes with surgery before their fee line''s effective start (FEE-316)',
     'surgery_date outside effective_start to effective_end', 'Excluded and flagged',
     'ut_fact_episodes_surgery_window_boundaries', 'Upstream (contract dates or fee assignment)',
     'Revenue and completions if these episodes were counted on that line'),
    ('DQ-09', 'contract_fee_schedule', 'discount_pct entered as a whole percent (5.0, 12.0) next to fractions (0.1)',
     'discount_pct above 1', 'Fixed in gold: values above 1 divided by 100',
     'assert_discount_rate_is_a_fraction; ut_dim_fee_lines_discount_scale', 'Upstream (validate the field) and model',
     'Revenue if the entered value were applied literally (a 500% or 1200% discount)'),
    ('DQ-10', 'contract_fee_schedule', 'discount_pct blank',
     'discount_pct null', 'Fixed in gold: blank = no discount',
     'ut_dim_fee_lines_discount_scale', 'Model',
     'Revenue lost if a null discount nulled out the line''s revenue'),
    ('DQ-11', 'contract_fee_schedule', 'Discount on a platform-fee line (FEE-403); the rule does not say whether discounts apply to platform fees',
     'PLATFORM_FEE line with discount_pct set', 'Decision: discount applied (rule says "fee line")',
     'ut_dim_fee_lines_discount_scale', 'Business (confirm contract terms)',
     'Revenue if the discount were not applied to platform fees'),
    ('DQ-12', 'contract_fee_schedule', 'Fee lines with no program (FEE-390, FEE-490)',
     'program_id null', 'Included under an "Unattributed" employer line',
     'not_null program_id (bronze, warn); ut_dim_fee_lines_orphan_unattributed', 'Upstream (contracting system)',
     'Revenue lost if these lines were dropped'),
    ('DQ-13', 'salesforce_accounts', 'Account hierarchy: duplicate account (EMP-102), union under its parent (EMP-104), parent that does not exist (EMP-108 -> EMP-150)',
     'parent_account_id differs from account_id; parent not in accounts; trailing space and case in name', 'Fixed in gold: rolled up to the ultimate parent; missing parent = own employer',
     'relationships parent_account_id (silver, warn); no_untrimmed_values (bronze, warn); ut_dim_employers_*', 'Upstream (Salesforce hygiene)',
     'Total unchanged; misattributed = revenue that would appear on a separate employer line without the roll-up'),
    ('DQ-14', 'salesforce_programs', 'Program went live after its fee lines started (Harrow: fee lines 2026-04-01, go-live 2026-05-01)',
     'go_live_date later than the fee line effective_start', 'Decision: follow the fee window (April platform fee recognized; pacing from the window); flagged',
     'none (flag is_go_live_after_window_start)', 'Business (contract vs launch date)',
     'Revenue if platform fees started at go-live; pacing effect in detail'),
    ('DQ-15', 'netsuite_billing_adjustments', 'Memo delivered twice',
     'Rows identical in every column', 'Fixed in silver: collapsed',
     'no_exact_duplicate_rows (bronze, warn); ut_stg_adjustments_exact_duplicates_collapsed', 'Upstream (extract) and model',
     'Revenue if the duplicate were counted twice'),
    ('DQ-16', 'netsuite_billing_adjustments', 'billing_month not in YYYY-MM (MM/YYYY, YYYY-M)',
     'Pattern match on billing_month', 'Fixed in silver: all three formats parsed',
     'billing_month_is_iso (bronze, warn); ut_stg_adjustments_billing_month_formats', 'Upstream (one format) and model',
     'Revenue if these memos were dropped by a strict parse'),
    ('DQ-17', 'netsuite_billing_adjustments', 'Memo on a program not in Salesforce',
     'program_id not in programs', 'Included under the "Unattributed" employer line',
     'relationships adjustments.program_id (silver, warn); ut_fact_revenue_orphan_adjustment_unattributed', 'Upstream (NetSuite program mapping)',
     'Revenue if the memo were dropped'),
    ('DQ-18', 'netsuite_billing_adjustments', 'Memos for Q2 months posted after the as-of date',
     'posted_date after the as-of date', 'Decision: included and flagged',
     'ut_fact_revenue_late_posted_adjustment_included_and_flagged', 'Business (close cut-off policy)',
     'Revenue if memos posted after the as-of date were excluded'),
    ('DQ-19', 'netsuite_billing_adjustments', 'Outlier memo: round amount, out-of-sequence ID, over 5x the median',
     'abs(adjustment_usd) over 5x the median absolute memo', 'Included as posted; flagged for Finance to confirm',
     'none (this register)', 'Upstream (Finance to confirm)',
     'Revenue if the memo were voided'),
    ('DQ-20', 'netsuite_billing_adjustments', '"Credit" memos with a positive amount',
     'reason contains "credit" and adjustment_usd above 0', 'Included as posted; flagged for Finance to confirm the sign',
     'none (this register)', 'Upstream (Finance to confirm)',
     'Revenue if the sign were flipped to a credit'),
    ('DQ-21', 'care_platform_episodes', 'invoice_month lags the surgery month',
     'invoice_month differs from the surgery month', 'Not used for reporting: the rule says surgery month',
     'ut_fact_episodes_reporting_month_is_surgery_month', 'Model (reporting rule)',
     'Revenue shift if Q2 were reported by invoice month'),
    ('DQ-22', 'care_platform_episodes', 'SCHEDULED episodes whose surgery date has passed',
     'Current status SCHEDULED and surgery_date on or before the as-of date', 'Counted as not completed (as recorded); flagged',
     'none (this register)', 'Upstream (status updates lag)',
     'Not quantified: may be unrecorded completions; potential in detail')
)

select
    catalog.issue_id,
    catalog.source_file,
    catalog.issue,
    catalog.detection,
    metrics.rows_affected,
    cast(round(metrics.q2_revenue_impact_usd, 2) as decimal(18, 2))        as q2_revenue_impact_usd,
    cast(round(metrics.q2_revenue_misattributed_usd, 2) as decimal(18, 2)) as q2_revenue_misattributed_usd,
    metrics.pacing_completed_impact,
    catalog.impact_basis,
    metrics.detail,
    catalog.handling,
    catalog.caught_by_test,
    catalog.fix_belongs
from catalog
join metrics using (issue_id)
