{{ config(alias='fact_episodes') }}

-- Grain: one row per episode that has at least one status record on or before as_of_date.
-- Current status = the episode's most recent record on or before as_of_date. Records written
-- after as_of_date are ignored for status (the extract is dated 2026-06-30, so they cannot be
-- trusted as of that date) but are summarized in later_* columns so their effect stays visible.
--
-- is_revenue_eligible marks the completed episodes that earn the case rate. A completed episode
-- is excluded, with the reason in revenue_exclusion_reason, when it is a test record, bills to a
-- fee line that is not in the fee schedule, bills to a platform-fee line, has neither a surgery
-- date nor an invoice month, or its surgery month is outside its fee line's effective window.
-- Orphan fee lines (no program) stay eligible and roll up to the "Unattributed" employer.
--
-- surgery_month is the reporting month. When surgery_date is missing it falls back to
-- invoice_month (flagged in surgery_month_source): the episode is completed, so the revenue is
-- earned; only its month is uncertain (invoice_month lags surgery month for late-month surgeries).

with records as (
    select * from {{ ref('silver_stg_care_platform_episodes') }}
),

as_of_records as (
    select * from records where not is_recorded_after_as_of
),

current_record as (
    select *
    from as_of_records
    qualify row_number() over (partition by episode_id order by record_updated_at desc) = 1
),

history as (
    select
        episode_id,
        count(*) filter (where not is_recorded_after_as_of)  as records_as_of,
        min(record_updated_at)                               as first_recorded_at,
        bool_or(is_duplicated_in_source)                     as has_duplicate_source_rows,
        bool_or(is_test_record)                              as is_test_record,
        count(*) filter (where is_recorded_after_as_of)      as later_record_count,
        arg_max(episode_status, record_updated_at)           as latest_status_in_extract
    from records
    group by episode_id
),

fee_lines as (
    select * from {{ ref('gold_dim_fee_lines') }}
),

episodes as (
    select
        current_record.episode_id,
        current_record.member_id,
        current_record.fee_id,
        fee_lines.fee_type,
        fee_lines.program_id,
        fee_lines.employer_id,
        fee_lines.employer_name,
        current_record.procedure_category,
        current_record.provider_id,
        current_record.surgery_date,
        coalesce(
            cast(date_trunc('month', current_record.surgery_date) as date),
            current_record.invoice_month
        )                                                              as surgery_month,
        case
            when current_record.surgery_date is not null  then 'surgery_date'
            when current_record.invoice_month is not null then 'invoice_month_fallback'
        end                                                            as surgery_month_source,
        current_record.surgery_date_source_format,
        current_record.episode_status                                  as current_status,
        current_record.record_updated_at                               as current_status_at,
        current_record.invoice_month,
        history.first_recorded_at,
        history.records_as_of,
        history.has_duplicate_source_rows,
        history.is_test_record,
        history.later_record_count,
        history.latest_status_in_extract,
        history.latest_status_in_extract <> current_record.episode_status as is_status_changed_after_as_of,
        fee_lines.fee_id is null                                       as is_unknown_fee_line,
        coalesce(fee_lines.is_orphan, false)                           as is_orphan_fee_line,
        current_record.surgery_date is null                            as is_surgery_date_missing,
        -- With a surgery date, compare the date; with the invoice_month fallback, only the month
        -- is known, so it is outside only when that whole month misses the window.
        case
            when current_record.surgery_date is not null then
                current_record.surgery_date < fee_lines.effective_start
                or current_record.surgery_date > fee_lines.effective_end
            else
                current_record.invoice_month > fee_lines.effective_end
                or last_day(current_record.invoice_month) < fee_lines.effective_start
        end                                                            as is_surgery_outside_fee_window
    from current_record
    join history on history.episode_id = current_record.episode_id
    left join fee_lines on fee_lines.fee_id = current_record.fee_id
)

select
    *,
    case
        when current_status <> 'COMPLETED'                   then null
        when is_test_record                                  then 'test record'
        when is_unknown_fee_line                             then 'fee line not in fee schedule'
        when fee_type = 'PLATFORM_FEE'                       then 'billed to a platform-fee line'
        when surgery_month is null                           then 'surgery date and invoice month missing'
        when coalesce(is_surgery_outside_fee_window, false)  then 'surgery outside fee line window'
    end                                                      as revenue_exclusion_reason,
    current_status = 'COMPLETED' and revenue_exclusion_reason is null as is_revenue_eligible
from episodes
