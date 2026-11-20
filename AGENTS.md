# Answering questions about this data

For an LLM or analyst answering Finance and Client Success questions from `carrum.duckdb`
(build it with the README). Definitions live on each table and column: read them with
`select comment from duckdb_tables()` / `duckdb_columns()`, or in `models/gold/_gold.yml`.

## How to query

One shell command per query, from the repo root (no virtualenv needed):

```bash
duckdb -readonly carrum.duckdb -c "select ... from gold.agg_revenue_employer_monthly ..."
```

`-readonly` lets several sessions read at once and never changes the file.

## Query only these four tables

| Question is about | Table (schema `gold`) | Grain |
|---|---|---|
| Revenue by employer, month, quarter; the CFO view | `agg_revenue_employer_monthly` | employer × month |
| Revenue by program or service line | `agg_revenue_program_monthly` | program × month |
| Utilization, pacing, under-use, renewal risk, what to escalate | `agg_pacing_fee_line` | case-rate fee line, as of 2026-06-30 |
| Data problems; "can I trust this number?" | `rpt_data_quality_register` | issue |

Every answer is a single-table `select` with `where` / `group by`. Do not join, and do not query
other `gold`, `silver` or `bronze` tables: the business rules are already applied in these four.

## Standing rules

- Data is as of **2026-06-30**. Q2 2026 = April–June (`year_quarter = '2026-Q2'`).
- Revenue = `total_revenue_usd` = case-rate revenue + platform fees (after discount) + NetSuite adjustments.
- An employer is the ultimate parent account. `UNATTRIBUTED` is revenue with no valid program: report it as its own line; never drop it or assign it to an employer.
- `_usd` and episode columns add up across rows. `pacing_ratio` does not: for a group, use `sum(completed_episodes) / sum(expected_episodes)`.
- `client_success_action` is the escalation rule (a documented judgement); use it rather than inventing thresholds.
- Register impacts describe an alternative handling. Never add them to revenue.

## How to answer

1. Name the table and filters you used, and give the components behind a total.
2. Add a caveat from `rpt_data_quality_register` when it applies, e.g. late-posted memos in June adjustments, or revenue on the `UNATTRIBUTED` line.
3. If the tables cannot answer the question, say so and say what is missing. Do not estimate or extrapolate.

## Not answerable from this data

- Anything after 2026-06-30, forecasts, or full-year projections.
- Member, patient, provider, procedure or clinical-outcome questions (not in the exposed tables; member IDs are tokens).
- Savings delivered to employers, claims cost, or ROI (no cost or claims data).
- Invoices, cash collected, receivables (this is recognized revenue, not billing).
- Utilization per eligible member (no eligibility counts) and contract terms beyond rate, discount and projected volume.
