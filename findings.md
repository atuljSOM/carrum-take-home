# Findings

Carrum Health · Staff Analytics Engineer take-home. Covers the 2c data quality register, the
Part 3 write-up and Part 4. Every figure below is read from a saved query in `outputs/`
(regenerate with the README); none is typed by hand.

## Approach

1. **Profiled each CSV before modelling.** Every column of the five extracts was read as text, so
   format and type problems showed up as data instead of load errors: duplicates, status history,
   records after the extract date, mixed date and discount formats, orphan keys, test records.
   The 31 labelled checks are in `scripts/profile_raw_csvs.sql` (`duckdb < scripts/profile_raw_csvs.sql`);
   each issue they found is a sized row in the register below.
2. **Designed before building.** Sketched the business flow (employer → program → fee line →
   episode, with NetSuite adjustments on the program) and a star schema, then one question at a
   time: who asks it, which rules apply, which data issues change the answer, what the rules leave
   open.
3. **Handled each issue in the right layer.** Bronze is an exact copy plus a contract that fails
   on drift and warns on known defects; silver parses, deduplicates and flags; gold applies the
   business rules. One episode fact feeds both revenue and pacing, so 2a and 2b cannot disagree.
4. **Wrote down every business assumption** where the brief's rules are silent, before code relied
   on it (see Assumptions), and sized each data issue in the register (2c).
5. **Verified** with reconciliation and unit tests, deliberately broken copies to confirm the tests
   fail, and an independent re-derivation of 2a and 2b straight from the CSVs.

## Part 2 answers

Queries in `analyses/`, results in `outputs/`.

- **2a:** Q2 2026 recognized revenue is **$1,280,857.19**: case $1,052,085.00, platform fees $310,500.00, adjustments −$81,727.81. One row per employer per month, plus quarter totals.
- **2b:** escalate FEE-307 (Marston Cardiac), FEE-312 (Bayview Bariatric Pilot), FEE-303 (Alder Ridge Bariatric), FEE-305 (Bayview Union Cancer Care), FEE-304 (Bayview Joint & Spine); watch FEE-316, FEE-311, FEE-310.

**Why the 2b ranking is what it is.** Lines are ranked by pacing ratio, as asked, but a ratio alone
overstates small or new lines, so escalation also needs at least $40,000 at risk, 60 days into the
window, an employer to call and no go-live gap (a judgement, documented on the pacing table).
Three escalated lines are Bayview's, so it is one account-level conversation, and its bariatric
pilot (FEE-312) has closed: that ratio is final and the renewal decision is now. Harrow is watch,
not escalate: it went live a month after its fee window opened, and pro-rated from go-live it paces
at 0.79, not 0.58 (register DQ-14). FEE-316 is one month old, so a single episode swings it.

## 2c · Data quality register

`gold.rpt_data_quality_register`, one row per issue, rebuilt on every `dbt build`: counts and
dollar effects are computed from the models, so they cannot drift from the data. Each effect is
measured against a stated naive handling: it is how wrong the number would be without the fix,
not an adjustment to add. Q2 revenue effects are net of discount. How each issue was detected, the
exact basis of its effect and the affected record IDs are in
`outputs/q2c_data_quality_register.csv`.

| ID | Issue | Rows | Effect if not handled | Handling | Caught by | Real fix |
|---|---|---|---|---|---|---|
| DQ-09 | discount_pct entered as a whole percent (5.0, 12.0) next to fractions (0.1) | 2 | −$1,336,500.00 Q2 revenue if the entered value were applied literally (a 500% or 1200% discount) | Fixed in gold: values above 1 divided by 100 | assert_discount_rate_is_a_fraction; ut_dim_fee_lines_discount_scale | Upstream (validate the field) and model |
| DQ-10 | discount_pct blank | 13 | −$901,900.00 Q2 revenue if a null discount nulled out the line's revenue | Fixed in gold: blank = no discount | ut_dim_fee_lines_discount_scale | Model |
| DQ-07 | Completed episodes billed to a platform-fee line (FEE-403) | 6 | +$162,000.00 Q2 revenue if these episodes were priced at the platform line's rate | Excluded and flagged; not remapped | ut_fact_episodes_revenue_exclusion_reasons | Upstream (billing assignment) |
| DQ-12 | Fee lines with no program (FEE-390, FEE-490) | 2 | −$81,000.00 Q2 revenue if these lines were dropped | Included under an "Unattributed" employer line | not_null program_id (bronze, warn); ut_dim_fee_lines_orphan_unattributed | Upstream (contracting system) |
| DQ-01 | Exact duplicate status records | 22 | +$62,431.00 Q2 revenue, +21 completions in pacing if each copy of a current COMPLETED record were counted | Fixed in silver: collapsed, copies counted in source_row_count | no_exact_duplicate_rows (bronze, warn); ut_stg_episodes_exact_duplicates_collapsed | Upstream (extract) and model |
| DQ-13 | Account hierarchy: duplicate account (EMP-102), union under its parent (EMP-104), parent that does not exist (EMP-108 -> EMP-150) | 3 | Total unchanged; $62,247.54 of Q2 revenue on the wrong employer line without the roll-up | Fixed in gold: rolled up to the ultimate parent; missing parent = own employer | relationships parent_account_id (silver, warn); no_untrimmed_values (bronze, warn); ut_dim_employers_* | Upstream (Salesforce hygiene) |
| DQ-18 | Memos for Q2 months posted after the as-of date | 4 | +$57,093.97 Q2 revenue if memos posted after the as-of date were excluded | Decision: included and flagged | ut_fact_revenue_late_posted_adjustment_included_and_flagged | Business (close cut-off policy) |
| DQ-19 | Outlier memo: round amount, out-of-sequence ID, over 5x the median | 1 | +$42,500.00 Q2 revenue if the memo were voided | Included as posted; flagged for Finance to confirm | none (this register) | Upstream (Finance to confirm) |
| DQ-20 | "Credit" memos with a positive amount | 2 | −$28,997.74 Q2 revenue if the sign were flipped to a credit | Included as posted; flagged for Finance to confirm the sign | none (this register) | Upstream (Finance to confirm) |
| DQ-04 | Surgery dates in MM/DD/YYYY | 9 | −$28,735.00 Q2 revenue, −9 completions in pacing if these dates were left unparsed and the episodes dropped | Fixed in silver: parsed month first | castable_to surgery_date (bronze, warn); ut_stg_episodes_surgery_date_both_formats | Upstream (one date format) and model |
| DQ-03 | Records dated after the 2026-06-30 extract date | 92 | +$22,272.00 Q2 revenue, +7 completions in pacing if the latest record in the whole extract were used | Excluded from current status; summarized in later_* columns | ut_stg_episodes_recorded_after_as_of_boundary; ut_fact_episodes_records_after_as_of_ignored | Upstream (extract date or timestamps are wrong) |
| DQ-02 | Completions later reversed in the status log | 7 | +$21,256.00 Q2 revenue, +7 completions in pacing if every COMPLETED record counted, not the current status | Fixed in gold: current status = latest record | ut_fact_episodes_current_status_is_latest_record | Model (the log is correct by design) |
| DQ-08 | Completed episodes with surgery before their fee line's effective start (FEE-316) | 4 | +$16,800.00 Q2 revenue, +4 completions in pacing if these episodes were counted on that line; FEE-316 pacing 0.54 -> 1.25 | Excluded and flagged | ut_fact_episodes_surgery_window_boundaries | Upstream (contract dates or fee assignment) |
| DQ-05 | Completed episodes with no surgery date | 5 | −$16,100.00 Q2 revenue, −5 completions in pacing if these episodes were excluded | Fixed in gold: reported in invoice_month, flagged in surgery_month_source | not_null surgery_date (bronze, warn); ut_fact_episodes_missing_surgery_date_falls_back_to_invoice_month | Upstream (required field) |
| DQ-21 | invoice_month lags the surgery month | 18 | +$15,972.00 Q2 revenue if Q2 were reported by invoice month | Not used for reporting: the rule says surgery month | ut_fact_episodes_reporting_month_is_surgery_month | Model (reporting rule) |
| DQ-16 | billing_month not in YYYY-MM (MM/YYYY, YYYY-M) | 2 | +$14,531.46 Q2 revenue if these memos were dropped by a strict parse | Fixed in silver: all three formats parsed | billing_month_is_iso (bronze, warn); ut_stg_adjustments_billing_month_formats | Upstream (one format) and model |
| DQ-14 | Program went live after its fee lines started (Harrow: fee lines 2026-04-01, go-live 2026-05-01) | 1 | −$12,500.00 Q2 revenue if platform fees started at go-live; FEE-311 pacing 0.58 -> 0.79 if pro-rated from go-live 2026-05-01 | Decision: follow the fee window (April platform fee recognized; pacing from the window); flagged | none (flag is_go_live_after_window_start) | Business (contract vs launch date) |
| DQ-11 | Discount on a platform-fee line (FEE-403); the rule does not say whether discounts apply to platform fees | 1 | +$9,000.00 Q2 revenue if the discount were not applied to platform fees | Decision: discount applied (rule says "fee line") | ut_dim_fee_lines_discount_scale | Business (confirm contract terms) |
| DQ-15 | Memo delivered twice | 1 | −$5,039.37 Q2 revenue if the duplicate were counted twice | Fixed in silver: collapsed | no_exact_duplicate_rows (bronze, warn); ut_stg_adjustments_exact_duplicates_collapsed | Upstream (extract) and model |
| DQ-17 | Memo on a program not in Salesforce | 1 | +$3,150.00 Q2 revenue if the memo were dropped | Included under the "Unattributed" employer line | relationships adjustments.program_id (silver, warn); ut_fact_revenue_orphan_adjustment_unattributed | Upstream (NetSuite program mapping) |
| DQ-06 | Test records (provider PRV-TEST, member TEST-*) on fee line FEE-999, which is not in the schedule | 15 | 15 completed test episodes would inflate episode counts; their fee line has no rate | Excluded and flagged | relationships episodes.fee_id (silver, warn); ut_stg_episodes_test_record_flag | Upstream (test data in a production extract) |
| DQ-22 | SCHEDULED episodes whose surgery date has passed | 6 | up to $19392.00 Q2 revenue and 6 completed episodes if these were actually completed; 6 of them are COMPLETED in records after the as-of date | Counted as not completed (as recorded); flagged | none (this register) | Upstream (status updates lag) |

**Fail vs warn.** A test errors when a violation would silently change a reported number (broken
grain, an unknown status, a key that cannot join, a reconciliation that does not tie). It warns
when the model already handles the defect, with the known count in its description, once per
defect at the first layer it is visible: 10 warnings, one per handled defect. A changed count
means the data changed. DQ-19, DQ-20 and DQ-22 have no test: they need a person (Finance or the
care platform) to confirm, so the register reports them rather than the build.

**Upstream vs model.** Most fixes belong upstream: one date format, required surgery dates,
validated discounts, no test records in production extracts, a program on every fee line and
memo. The model handles each so the numbers are right today, and flags them so the upstream fix
can be verified when it lands.

## Assumptions

Decisions the brief's rules do not settle. Each is documented on the model that applies it
(`models/**/_*.yml`).

| Decision | Why |
|---|---|
| Current status = latest record **on or before** 2026-06-30; 92 later records ignored | The extract is dated 2026-06-30; later records cannot be known as of it |
| Q2 memos posted after 2026-06-30 included and flagged | Finance books June true-ups in July as part of the Q2 close |
| Missing surgery date → invoice month, flagged | A completed episode is earned; only its month is uncertain |
| `discount_pct` above 1 = whole percent; blank = 0; applies to platform fees | Hand-entered mixed scales; the rule says "fee line" |
| Episodes on a platform-fee line, test records, unknown fee lines, surgery outside the fee window: excluded, flagged | No contracted case rate applies |
| Platform fee every month the fee line is effective, even before go-live | The rule keys on the fee line, not the program |
| Revenue with no valid program kept on an "Unattributed" line | Keeps the quarter total complete and reconcilable |
| Employer = ultimate parent account; missing parent = own employer | "One employer is one line" |
| Pacing pro-rated by days, as-of date inclusive; completed = the episodes that earn revenue | Pacing and revenue cannot disagree |

## Part 3 · Pipeline an LLM can use

**What I changed and why.** The LLM queries four gold tables only, each answering its questions
with a single-table select, so the business rules are applied once in dbt and never re-derived in
a prompt: revenue by employer, revenue by program and service line, pacing per fee line (with the
escalation rule as a column), and the data quality register. Their yml follows a metric-view
convention: what each table already applies, what it cannot be sliced by, every column marked as
a dimension or measure, and which measures must not be summed (`pacing_ratio`). `persist_docs`
writes those definitions into `carrum.duckdb`, so an LLM that only opens the database still reads
them; a test fails the build if any column on those tables loses its comment. `AGENTS.md` routes
questions to tables, states the standing rules (as-of date, what revenue means, the
Unattributed line) and lists what the data cannot answer, so the model declines instead of
estimating. Most of this is changes to existing models; the only new model is the program-level
revenue table, and the employer table is now a roll-up of it so the two cannot disagree.

**How I checked it.** `eval/` runs headless Claude Code on a fresh clone with a generic
instruction and read-only access to the database, on eight questions: the two Part 2 questions,
three phrased the way a VP would ask, and three the data cannot answer (a full-year forecast,
savings versus claims, surgeon volumes). Answers are graded against the marts. The first run
passed all eight, but the transcripts showed some answers were taken from files, not queries;
I fixed the project (the query command in `AGENTS.md`, employer names on flagged memos in the
register), not the instruction, and re-ran: every answer queried the database.
_[Pending: results of the current eval run, `eval/results/…`]_

**Before Finance relies on an LLM for a number.**
- Every answer shows its SQL against the four tables, and the number reproduces from that SQL.
- A larger question set, run repeatedly, giving the same number every time, including adversarial
  phrasings and questions just outside the data.
- The eval runs in CI on every change to the gold models, so a model change cannot silently
  change an answer.
- Finance signs off the revenue definition and the escalation thresholds before they are served.
- On real PHI: the LLM sees only aggregate gold tables (no member or provider rows), runs under a
  zero-retention agreement, with a read-only role scoped to those tables, and every query logged.

## Part 4a · Analytics engineering strategy

**First three things, in order.**
1. **Contracts on the five extracts and a data quality register.** Unblocks trust: every known
   defect is counted on each load, so the upstream owners (contracting, Salesforce, care platform,
   NetSuite) get a concrete, sized fix list instead of a complaint.
2. **One episode fact and one revenue fact, with reconciliation tests.** Unblocks a single Q2
   number: Finance's close and Client Success's pacing read the same definition of a completed
   episode, so their answers cannot disagree.
3. **Pacing at fee-line grain with the escalation rule.** Unblocks renewal conversations: Client
   Success gets a ranked, explained list instead of a hand-built spreadsheet.

**One canonical metric.** *Recognized revenue* for a month = Σ (completed episodes whose surgery
was that month, as of the reporting date × case rate × (1 − discount)) + Σ (platform fees for each
month a fee line is effective × (1 − discount)) + NetSuite adjustments for that billing month. The
Controller owns the definition; Client Success and Contracting must agree to the edges it
settles (as-of cut-off, late memos, discount scale, unattributed revenue). It lives in
`gold_fact_revenue_monthly`, with the definition on the model's yml, and is consumed only through
the revenue aggregates.

**Four new analysts: nobody silently changes the revenue number.**
- CI runs `dbt build` on every PR (modified models and everything downstream) against a fixed
  extract; the reconciliation and unit tests are errors, so a changed rule fails the PR.
- A pinned regression check: the Q2 2026 total and its components on the frozen extract. A PR
  that moves them must say so and why.
- Enforced contracts on the four LLM-facing tables; breaking changes ship as a new model version.
- CODEOWNERS on `models/gold/fact/` and the revenue aggregates: Finance-facing changes need my
  review and a Finance sign-off on the PR, which states before/after numbers.
- Definitions live once, in the model yml; nothing re-derives revenue in a dashboard or prompt.

**What I would not build in the first quarter.** Dashboards, and any semantic layer that redefines
metrics outside dbt: until Finance and Client Success sign off the definitions, each one becomes
another place the number can differ. BI reads the gold aggregates as they are. Also not yet: an
in-house chatbot UI, forecasting or full-year projections, and incremental models. Each will be
asked for; none helps until the definitions are agreed and the upstream fixes land.

## Part 4b · AI usage log

Tool: Claude Code (Opus 5.5/Sonnet 5.5 ) in VS Code, on every part. Per-step log (asked / did / checked):
`docs/AI_LOG.md`.

- **Part 1:** scaffold and environment, raw-data profiling, the medallion design (my
  conventions), models, unit and reconciliation tests. I set the rules and decisions; it wrote
  most SQL and yml, and I trimmed tests and docs it over-produced.
- **Part 2:** brainstormed each question in chat before building; it drafted the answer queries
  and the register; I had independent agents re-derive 2a and 2b from the CSVs to check the marts.
- **Part 3:** it built the LLM-facing layer to a metric-view convention I directed, and the eval
  harness; I chose the fixes from the eval transcripts.
- **Checking:** every model change was verified by rebuilding and re-exporting the answers;
  deliberate breaks ("mutation checks") confirmed each new test fails when it should.

## Part 4c · One catch

**Inferring how a record was made.** Account EMP-102 is "alder ridge logistics " (lowercase,
trailing space). The assistant called it hand-typed, a claim about how the record was entered that
nothing in the extract can show. When I challenged it, it overcorrected to "not a duplicate",
which was just as unsupported. 

**Other corrections along the way.**
- A pacing estimate given in chat (Harrow 0.86 from go-live) was wrong; the register's computed figure is 0.79.
- The register listed IDs in arbitrary order, so the 2c output changed between builds with no data change.
- The first eval passed, but its transcripts showed some answers read from files rather than queried.
- The assistant over-produced tests (one defect warned in four layers); trimmed to one warning per defect.

## With more time

- Run the eval on every change to the LLM-facing tables, their definitions or `AGENTS.md` (and
  nightly), with repeated runs per question, so a rename or reworded definition cannot silently
  change an answer.
- Enforced dbt contracts and versions on the LLM-facing tables.
- Snapshots (SCD2) of the fee schedule, programs and accounts: today a corrected rate or discount
  silently restates every past month. Plus a frozen record of each close, so the Q2 number as
  reported stays separate from later restatements (late memos, late status changes).

