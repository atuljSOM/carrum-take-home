# Staff Analytics Engineer
**Carrum Health | Take-Home Exercise**

> Markdown transcription of `Staff_Analytics_Engineer_Take_Home.docx` (same folder). The .docx is the original.

Return it within 5 days. Spend as much or as little time on it as you want. We know you have a job. We are not measuring hours, and there is no credit for grinding. Build the parts you can build well, and write down what you would have done with more time. We read that section closely.

AI tooling is encouraged. Use whatever you normally use to write code and SQL. We ask you to disclose how you used it in Part 4. Not using AI is a neutral choice. Using it without validating the output is not.

**We will run your work.** A reviewer will clone your repo, follow your README on a Mac laptop, run `dbt build`, run your queries, point an LLM at the result, and ask it questions you have not seen. If it does not run from a clean checkout, we will not be able to give you credit for it.

---

## The situation

You are joining Carrum Health. Carrum contracts with self-insured employers to give their members access to high-quality surgery and cancer care at Centers of Excellence, for a bundled price. Carrum earns revenue two ways: a **case rate** for each completed care episode, and a **monthly platform fee** for the program.

Employer accounts and programs live in Salesforce. Contract fee terms live in the contracting system. Episode activity comes from the care platform, which logs every status change. Finance posts credits, guarantee true-ups and fees in NetSuite. Nobody owns the join.

Finance needs a **Q2 2026 revenue number** they can defend. Client Success needs to know which employer programs are **under-utilizing their contract** before the renewal conversation, because low utilization means members are not getting to care and the employer is not seeing the savings they bought. Today both questions get answered by hand, differently each time, and the answers do not match.

Your job is to build the layer that makes those answers repeatable: a dbt project on DuckDB, the SQL that answers the questions from that project, and a pipeline that an LLM can ingest to answer questions about the data reliably.

You have five CSV extracts in the `data` folder. The data is synthetic, but it is shaped like an extract from our systems, not like a cleaned teaching dataset.

---

## The data

| File | Columns | Notes |
|---|---|---|
| `salesforce_accounts.csv` | account_id, account_name, parent_account_id, industry, funding_type | Employer client accounts. Some accounts are subsidiaries, unions or affiliated groups of another account. |
| `salesforce_programs.csv` | program_id, account_id, program_name, service_line, tpa_name, go_live_date, term_end_date | One row per employer benefit program (for example, an employer's orthopedic and spine surgery benefit). |
| `contract_fee_schedule.csv` | fee_id, program_id, fee_type, rate, projected_episodes, discount_pct, effective_start, effective_end | The contract terms. `fee_type` is `CASE_RATE` or `PLATFORM_FEE`. For case-rate lines, `projected_episodes` is the episode volume Carrum and the employer projected over the fee line's full effective window. |
| `care_platform_episodes.csv` | episode_id, member_id, fee_id, procedure_category, provider_id, surgery_date, episode_status, invoice_month, record_updated_at | Episode activity from the care platform, extracted on **2026-06-30**. The platform writes a new row every time an episode changes status (REFERRED, SCHEDULED, COMPLETED, CANCELLED). `invoice_month` is populated by an upstream billing job. `member_id` is a synthetic token. |
| `netsuite_billing_adjustments.csv` | memo_id, program_id, billing_month, adjustment_usd, reason, posted_date | Credit memos, performance guarantee credits, savings guarantee true-ups and fees posted by Finance. |

---

## Business rules

Use these exactly. If a rule does not cover a case you hit, decide, and write down the decision.

- **Case-rate revenue** equals the fee line's rate for each episode whose current status is `COMPLETED`. The current status of an episode is its most recent record.
- **Platform fee revenue** equals the rate, recognized in full for each calendar month the fee line is effective. It is not a function of episodes.
- **Discounts** apply to gross revenue for the fee line. The `discount_pct` field was entered by humans in the contracting tool over several years.
- **Adjustments** apply at the program and month level, and are added after discounted revenue.
- **Reporting month** is the month in which the surgery actually occurred.
- **Pacing** compares completed episodes to `projected_episodes`, pro-rated to the share of the fee line's effective window that has elapsed as of 2026-06-30.

---

## Technical requirements

- **Database:** local DuckDB. A single `.duckdb` file on your machine. No cloud warehouse, no Docker requirement.
- **Transformation:** dbt Core with the `dbt-duckdb` adapter. Pin your versions (requirements.txt, uv, or poetry). Include a `profiles.yml` in the repo, or exact instructions to create one.
- **Part 3 stands on the repo alone.** Everything an LLM could use is in your repo and the DuckDB file your README builds. We will not hand it anything else.
- **Reproducible from a clean clone.** One README with the exact commands, in order, from `git clone` to answers.

---

## Part 1. The dbt project

Model the five sources into a dbt project that answers the questions in Part 2 and that the next analytics engineer could build on without asking you how it works.

- **Load the raw CSVs through dbt.** Sources reading the files in place (dbt-duckdb supports external locations), seeds, or another approach. Your choice; tell us why.
- **Layer it.** Staging models that are 1:1 with sources (renaming, casting, parsing, light cleaning); intermediate models where they earn their place; marts that a consumer would query. State the grain of every mart.
- **Put the business rules in the models, not in the answer queries.** Parameterize the as-of date.
- **Test it.** Generic tests on keys and relationships, plus at least two singular tests that encode a business rule or a reconciliation. Decide which data problems should fail the build and which should warn, and tell us why.
- **Document it.** Descriptions on every mart and its important columns. `dbt docs generate` must succeed.
- **`dbt build` must complete without errors.** Warnings are fine if they are intentional and explained.

*Not required: incremental models, snapshots, or packages. You may use them if they help.*

---

## Part 2. SQL against your marts

Write the SQL that answers each question. Every answer query must read **only from your marts**, either as dbt analyses using `ref()` or as plain SQL against the marts schema. No reads from raw files or staging models. If a question cannot be answered from your marts, that is a modeling gap: fix the model, not the query. Favor readable CTEs over cleverness.

### 2a. Recognized revenue by employer and month for Q2 2026

April, May and June. Report at the level a CFO would want: one row per employer per month, rolled up so that one employer is one line. Show the components (case revenue, platform fees, adjustments) and include a quarter total.

### 2b. Utilization risk

Return the case-rate fee lines pacing worst against projection as of 2026-06-30. For each, show completed episodes, expected episodes, pacing ratio, and the revenue at risk if the shortfall is never made up. Tell us which ones you would actually escalate to Client Success, and why the ranking is what it is.

### 2c. Data quality register

List every problem you found in this data. For each one: what it is, how you detected it, how much it moves the numbers in 2a or 2b, whether you fixed it in the model or excluded it, which dbt test (if any) now catches it, and whether the real fix belongs upstream or in the model.

Be specific about magnitude. "There are some duplicates" is not an answer. "31 exactly duplicated rows, inflating quarter revenue by $87,420" is. **We care more about 2c than about 2a matching our number.**

---

## Part 3. Pipeline an LLM can use

Carrum wants to put an LLM on top of this pipeline so Finance and Client Success can ask questions about the data and get accurate answers, with no analyst in between. The LLM will know only what it can read from your pipeline, and **a confident wrong number is worse than no answer.**

Build your pipeline so that an LLM can ingest it and answer questions about this data reliably and consistently, including recognizing the questions the data cannot answer. We are deliberately not telling you how. We want to see how you get there.

**How we will look at it.** A reviewer will give an LLM access to your repo and your built DuckDB file, with only a generic instruction, and ask it questions you have not seen. They include the Part 2 questions, questions worded the way a busy VP would word them, and some the data cannot answer. We will score the answers and trace the misses back to your project.

**Keep it small.** This part is not meant to be a big build. Most of the work should be changes to the project you already have, not new infrastructure. If you pass a couple of hours here, stop and put the rest in your write-up.

**Optional: a chatbot.** If you want to test your work, you may put any interface you like on top: a script, a notebook, an off-the-shelf agent pointed at your DuckDB file. It earns no credit by itself, and skipping it costs nothing. If you do it, tell us what it got wrong and what you changed in the project because of that. The data is synthetic, so any model is fine, but say what would change on real PHI. If we cannot run it (credentials, a large model), include a transcript instead.

**In your write-up (half a page):** what you changed and why, how you checked that it works, and what you would need to see before Finance relied on an LLM for a number.

---

## Part 4. Write-up

One document (`findings.md` or PDF) that covers the 2c register, the Part 3 write-up, and the following.

### 4a. Analytics engineering strategy

One page maximum. Prose or bullets. Assume you are three weeks into the job and these five sources are all you have.

- What are the first three things you build or change, in order, and what does each one unblock?
- Name one metric from this exercise, define it canonically, say who has to agree to that definition before it goes on a dashboard, and say where in the dbt project that definition should live.
- Four analysts will start contributing to this project next quarter. What do you put in place so nobody can silently change the revenue number? Be concrete: CI, tests, contracts, ownership, review.
- What would you not build in the first quarter, even though someone will ask for it?

We are looking for judgment under constraint, not a maturity model.

### 4b. AI usage log

Short and factual. Which tools, on which parts, and what you asked them to do.

### 4c. One catch

Show us one place where an AI tool gave you something wrong, misleading or subtly incomplete on this exercise, either while you were building or while testing your Part 3 work. Include what it produced, how you noticed, and what you did. If nothing went wrong, tell us what you checked in order to be confident of that.

---

## Deliverables

- A git repository (zip or link) containing your dbt project, your Part 2 SQL, your Part 3 changes (and the optional tool, if you built one), and a README with exact setup and run commands.
- Your Part 2 outputs, as CSV files in the repo.
- Your Part 3 write-up. If you built the optional tool, include any evaluation questions and results or a transcript.
- The findings document covering 2c, the Part 3 write-up, and Part 4.
- Anything else you built that you want us to see.

## Ground rules

- Five days to return it, and no expectation about hours spent. All four parts are required, but a small version that works and is honestly described beats an ambitious one that does not run.
- **State your assumptions in writing.** Undocumented assumptions are the thing we are hiring against.
- The data is synthetic, so you may use it with any AI coding assistant while you build.
- **Do not build a dashboard.** We know you can. This exercise is about what sits underneath one.
