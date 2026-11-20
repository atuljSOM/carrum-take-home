-- Raw-CSV profiling for the Carrum take-home.
-- Run from the repo root:  duckdb < scripts/profile_raw_csvs.sql   (in-memory; does not touch carrum.duckdb)
-- Every column is read as VARCHAR so format problems stay visible.

-- ============ PREAMBLE ============
create schema if not exists raw_sources;
create or replace view raw_sources.salesforce_accounts          as select * from read_csv('data/salesforce_accounts.csv',          all_varchar=true, header=true);
create or replace view raw_sources.salesforce_programs          as select * from read_csv('data/salesforce_programs.csv',          all_varchar=true, header=true);
create or replace view raw_sources.contract_fee_schedule        as select * from read_csv('data/contract_fee_schedule.csv',        all_varchar=true, header=true);
create or replace view raw_sources.care_platform_episodes       as select * from read_csv('data/care_platform_episodes.csv',       all_varchar=true, header=true);
create or replace view raw_sources.netsuite_billing_adjustments as select * from read_csv('data/netsuite_billing_adjustments.csv', all_varchar=true, header=true);

-- episodes: exact-dedup, parse both date formats, attach fee line
create or replace view ep_p as
select distinct e.*,
       coalesce(try_strptime(e.surgery_date,'%Y-%m-%d'), try_strptime(e.surgery_date,'%m/%d/%Y'))::date as sd,
       e.record_updated_at::timestamp as ts,
       f.fee_type, f.program_id, f.rate::double as rate
from raw_sources.care_platform_episodes e left join raw_sources.contract_fee_schedule f using (fee_id);
-- current status = latest record (whole log) vs latest record on/before the as-of date
create or replace view ep_cur      as select * from ep_p qualify row_number() over (partition by episode_id order by ts desc) = 1;
create or replace view ep_cur_asof as select * from ep_p where ts < timestamp '2026-07-01'
                                     qualify row_number() over (partition by episode_id order by ts desc) = 1;

-- ============ salesforce_accounts ============
-- A1 duplicate account by normalized name
select 'A1 dup name' as chk, lower(trim(account_name)) as norm_name, string_agg(account_id, ',') as ids
from raw_sources.salesforce_accounts group by 2 having count(*) > 1;
-- A2 whitespace / case problems in names
select 'A2 untrimmed name' as chk, account_id, '[' || account_name || ']' as name from raw_sources.salesforce_accounts where account_name <> trim(account_name);
-- A3 parent that does not exist
select 'A3 orphan parent' as chk, account_id, parent_account_id from raw_sources.salesforce_accounts
where parent_account_id not in (select account_id from raw_sources.salesforce_accounts);
-- A4 hierarchy: who rolls up under whom (top-level accounts point at themselves, not NULL)
select 'A4 hierarchy' as chk, account_id, account_name, parent_account_id, account_id = parent_account_id as is_self_parent from raw_sources.salesforce_accounts order by parent_account_id, account_id;
-- A5 categorical values
select 'A5 categories' as chk, industry, funding_type, count(*) as n from raw_sources.salesforce_accounts group by all;

-- ============ salesforce_programs ============
-- P1 key + FK checks
select 'P1 keys' as chk, count(*) as rows, count(distinct program_id) as ids,
       count(*) filter (where account_id not in (select account_id from raw_sources.salesforce_accounts)) as orphan_account from raw_sources.salesforce_programs;
-- P2 programs whose account is a duplicate / child account (affects employer roll-up)
select 'P2 program on child acct' as chk, p.program_id, p.program_name, a.account_id, a.parent_account_id
from raw_sources.salesforce_programs p join raw_sources.salesforce_accounts a using (account_id) where a.account_id <> a.parent_account_id;
-- P3 fee lines that start before the program goes live / end after term
select 'P3 fee outside program window' as chk, f.fee_id, f.fee_type, f.rate, f.effective_start, f.effective_end, p.go_live_date, p.term_end_date
from raw_sources.contract_fee_schedule f join raw_sources.salesforce_programs p using (program_id)
where f.effective_start < p.go_live_date or f.effective_end > p.term_end_date;
-- P4 categoricals + dates
select 'P4 categories' as chk, service_line, tpa_name, count(*) from raw_sources.salesforce_programs group by all order by 2;
select 'P4 date formats' as chk, regexp_replace(go_live_date,'[0-9]','9','g') as golive_pat, regexp_replace(term_end_date,'[0-9]','9','g') as term_pat, count(*) from raw_sources.salesforce_programs group by all;

-- ============ contract_fee_schedule ============
-- F1 discount_pct: mixed fraction vs whole-percent vs blank
select 'F1 discount form' as chk, fee_id, fee_type, rate, discount_pct,
       case when discount_pct is null then 'blank'
            when discount_pct::double < 1 then 'fraction'
            else 'whole-percent (likely 12 = 12%)' end as form
from raw_sources.contract_fee_schedule order by form, fee_id;
-- F2 Q2 effect of reading whole-percent values literally vs as percent
select 'F2 discount Q2 impact' as chk, c.fee_id, any_value(f.discount_pct) as discount_pct, count(*) as q2_completed,
       sum(c.rate) as gross,
       sum(c.rate * (1 - f.discount_pct::double))       as net_if_read_as_fraction,
       sum(c.rate * (1 - f.discount_pct::double / 100)) as net_if_read_as_percent
from ep_cur c join raw_sources.contract_fee_schedule f using (fee_id)
where c.episode_status = 'COMPLETED' and c.sd between date '2026-04-01' and date '2026-06-30'
  and f.discount_pct::double >= 1
group by 1, 2;
-- F3 fee lines with no program
select 'F3 no program' as chk, fee_id, fee_type, rate, projected_episodes from raw_sources.contract_fee_schedule where program_id is null;
-- F4 overlapping same-type lines on one program
select 'F4 overlap' as chk, a.program_id, a.fee_id, b.fee_id as other_fee_id, a.effective_start, a.effective_end, b.effective_start as other_start
from raw_sources.contract_fee_schedule a join raw_sources.contract_fee_schedule b on a.program_id = b.program_id and a.fee_id < b.fee_id and a.fee_type = b.fee_type
 and a.effective_start <= b.effective_end and b.effective_start <= a.effective_end;
-- F5 shape checks: projected only on case rate, integer, windows valid
select 'F5 shape' as chk,
  count(*) filter (where fee_type = 'CASE_RATE' and projected_episodes is null) as case_no_projection,
  count(*) filter (where fee_type = 'PLATFORM_FEE' and projected_episodes is not null) as platform_with_projection,
  count(*) filter (where projected_episodes::double <> floor(projected_episodes::double)) as non_integer_projection,
  count(*) filter (where effective_end < effective_start) as end_before_start,
  count(*) - count(distinct fee_id) as dup_fee_id
from raw_sources.contract_fee_schedule;

-- ============ care_platform_episodes ============
-- E1 exact duplicate rows
select 'E1 exact dups' as chk, count(*) as dup_groups, sum(n - 1) as extra_rows
from (select *, count(*) as n from raw_sources.care_platform_episodes group by all having count(*) > 1);
select 'E1 dup rows by status' as chk, episode_status, count(*) from (select *, count(*) n from raw_sources.care_platform_episodes group by all having n > 1) group by all;
-- E2 status-history paths (after exact dedup)
select 'E2 status paths' as chk, path, count(*) as episodes
from (select episode_id, string_agg(episode_status, ' > ' order by ts) as path from ep_p group by 1) group by 2 order by 3 desc;
-- E3 records after the 2026-06-30 extract date, and how they change current status
select 'E3 post-extract rows' as chk, episode_status, count(*), min(ts), max(ts) from ep_p where ts >= timestamp '2026-07-01' group by all;
select 'E3 status flip' as chk, a.episode_status as status_full_log, coalesce(b.episode_status, '(no row yet)') as status_as_of_0630, count(*)
from ep_cur a left join ep_cur_asof b using (episode_id)
where a.episode_status is distinct from b.episode_status group by all;
-- E4 surgery_date format + nulls
select 'E4 surgery_date format' as chk, coalesce(regexp_replace(surgery_date,'[0-9]','9','g'), 'NULL') as pat, episode_status, count(*) from raw_sources.care_platform_episodes group by all order by 2;
select 'E4 null surgery_date' as chk, episode_id, fee_id, episode_status, invoice_month, record_updated_at from raw_sources.care_platform_episodes where surgery_date is null;
-- E5 invoice_month vs surgery month (reporting month is surgery month)
select 'E5 invoice != surgery month' as chk, strftime(sd,'%Y-%m') as surgery_month, invoice_month, count(*)
from ep_p where episode_status = 'COMPLETED' and invoice_month <> strftime(sd,'%Y-%m') group by all order by 2;
select 'E5 invoice populated only on COMPLETED' as chk, episode_status, count(*) filter (where invoice_month is null) as inv_null, count(*) filter (where invoice_month is not null) as inv_set from raw_sources.care_platform_episodes group by 2;
-- E6 fee_id integrity: unknown fee, platform fee used as case rate, fee with no program
select 'E6 bad fee link' as chk, e.fee_id, coalesce(e.fee_type, '(unknown fee)') as fee_type, e.program_id,
       count(*) as episodes, count(*) filter (where episode_status = 'COMPLETED') as completed
from ep_cur e where e.fee_type is null or e.fee_type <> 'CASE_RATE' or e.program_id is null group by all;
-- E7 test data
select 'E7 test records' as chk, provider_id, fee_id, count(*) as rows, count(*) filter (where member_id like 'TEST-%') as test_members
from raw_sources.care_platform_episodes where provider_id = 'PRV-TEST' or member_id like 'TEST-%' group by all;
-- E8 surgery date outside the fee line's effective window
select 'E8 outside fee window' as chk, c.episode_id, c.fee_id, c.sd, f.effective_start, f.effective_end, c.episode_status
from ep_cur c join raw_sources.contract_fee_schedule f using (fee_id) where c.sd < f.effective_start::date or c.sd > f.effective_end::date;
-- E9 attribute drift within an episode (should all be 0)
select 'E9 drift' as chk,
  count(*) filter (where n_mem > 1) as member, count(*) filter (where n_fee > 1) as fee,
  count(*) filter (where n_proc > 1) as proc, count(*) filter (where n_prv > 1) as provider, count(*) filter (where n_sd > 1) as surgery_date
from (select episode_id, count(distinct member_id) n_mem, count(distinct fee_id) n_fee, count(distinct procedure_category) n_proc,
             count(distinct provider_id) n_prv, count(distinct surgery_date) n_sd from raw_sources.care_platform_episodes group by 1);
-- E10 Q2 gross case revenue under different readings (rate x episodes, pre-discount, before any fixes)
select 'E10 naive: every COMPLETED row' as reading, count(*) as n, sum(f.rate::double) as usd
  from raw_sources.care_platform_episodes e join raw_sources.contract_fee_schedule f using (fee_id)
  where e.episode_status = 'COMPLETED' and coalesce(try_strptime(e.surgery_date,'%Y-%m-%d'), try_strptime(e.surgery_date,'%m/%d/%Y'))::date between date '2026-04-01' and date '2026-06-30'
union all select 'E10 current status, full log', count(*), sum(rate) from ep_cur where episode_status = 'COMPLETED' and sd between date '2026-04-01' and date '2026-06-30'
union all select 'E10 current status as of 2026-06-30', count(*), sum(rate) from ep_cur_asof where episode_status = 'COMPLETED' and sd between date '2026-04-01' and date '2026-06-30';

-- ============ netsuite_billing_adjustments ============
create or replace view adj_p as
select *, adjustment_usd::double as usd,
       strftime(coalesce(try_strptime(billing_month,'%Y-%m'), try_strptime(billing_month,'%m/%Y')),'%Y-%m') as bm
from raw_sources.netsuite_billing_adjustments;
-- N1 duplicate memo
select 'N1 dup memo' as chk, memo_id, count(*) as n, count(distinct (program_id, billing_month, adjustment_usd, reason, posted_date)) as distinct_versions
from raw_sources.netsuite_billing_adjustments group by 2 having count(*) > 1;
-- N2 billing_month formats
select 'N2 billing_month format' as chk, regexp_replace(billing_month,'[0-9]','9','g') as pat, count(*), string_agg(memo_id || '=' || billing_month, ', ') from raw_sources.netsuite_billing_adjustments group by 2;
-- N3 unknown program
select 'N3 orphan program' as chk, memo_id, program_id, billing_month, usd from adj_p where program_id not in (select program_id from raw_sources.salesforce_programs);
-- N4 sign by reason (credits should be negative)
select 'N4 sign by reason' as chk, reason, sign(usd) as sign, count(*), sum(usd) from adj_p group by all order by 2, 3;
-- N5 posted after the as-of date
select 'N5 posted after as-of' as chk, memo_id, program_id, bm, usd, posted_date from adj_p where posted_date > '2026-06-30';
-- N6 outliers (|usd| vs median)
select 'N6 outlier' as chk, memo_id, program_id, bm, usd, reason, round(abs(usd) / (select median(abs(usd)) from adj_p), 1) as x_median
from adj_p order by abs(usd) desc limit 3;
-- N7 Q2 totals under each treatment
select 'N7 strict YYYY-MM only' as reading, count(*), sum(usd) from adj_p where billing_month in ('2026-04','2026-05','2026-06')
union all select 'N7 months normalized', count(*), sum(usd) from adj_p where bm between '2026-04' and '2026-06'
union all select 'N7 normalized + deduped', count(*), sum(usd) from (select distinct * from adj_p) where bm between '2026-04' and '2026-06'
union all select 'N7 ...+ drop orphan PRG-299', count(*), sum(usd) from (select distinct * from adj_p) where bm between '2026-04' and '2026-06' and program_id <> 'PRG-299';
