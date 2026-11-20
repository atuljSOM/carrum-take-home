# AI Usage Log (4b)

**Tool:** Claude Code (Opus 5.5), VS Code

---

### 1. Project setup

- **Asked:** create the project folder and set it up to the brief's requirements
- **Did:** Python 3.11 venv, pinned dbt-core / dbt-duckdb / duckdb, in-repo `profiles.yml`, `as_of_date` var, CSV sources, README
- **Checked:** `dbt debug` passed; source read all 1,189 episode rows

### 2. Git repo

- **Asked:** create a private repo on my personal GitHub
- **Did:** created `atuljSOM/carrum-take-home`; set the personal identity for this repo only; pushed the scaffold
- **Checked:** commit author and remote are the personal account

### 3. DuckDB CLI

- **Asked:** set up DuckDB for interactive SQL
- **Did:** installed the DuckDB CLI via Homebrew (v2.0.0, same version as the Python package); the web UI (`duckdb -ui`) ships with it
- **Checked:** ran a test query against a CSV

### 4. CLAUDE.md

- **Asked:** write a minimal CLAUDE.md (spec link, run commands, raw-data and as-of rules, working rules, empty structure/decisions sections); remove a stray file
- **Did:** drafted it for review, then wrote it as approved; deleted an untracked file named `#` in the repo root
- **Checked:** read the spec, AI log and repo layout before drafting; confirmed `#` was an empty DuckDB file before deleting it

### 5. Raw-data profiling

- **Asked:** profile every column of the five CSVs for duplicates, status history, date formats and `discount_pct` issues, with runnable queries; no code changes
- **Did:** profiled with in-memory DuckDB; wrote a labelled query script outside the repo; found duplicate rows, status reversals, rows after the extract date, mixed date formats, mixed `discount_pct` scales, orphan keys and test records
- **Checked:** reconciled the Q2 revenue gap to its causes ($115,000 = duplicates + reversals); re-ran the script after renaming its views and diffed the output

### 6. Layer design and scaffold

- **Asked:** evaluate design considerations I provided against the brief, flag conflicts; then scaffold sources, bronze as a data contract, empty silver and gold
- **Did:** mapped staging / intermediate / marts onto silver `stg_` / `int_` / gold; built 5 sources, 5 bronze views with enforced contracts and 82 tests (6 custom); logic deferred
- **Checked:** `dbt build` passes with the 10 expected warnings; broke copies of the CSVs 8 ways and each failed the build

### 7. Medallion rules in README and CLAUDE.md

- **Asked:** make the medallion structure a standing rule, briefly
- **Did:** added short rule sets to CLAUDE.md and README; decided against a separate guidelines doc
- **Checked:** edits landed in this repo only (the chat's file links pointed at another repo)

### 8. Branch, commits and PR

- **Asked:** commit the scaffold and bronze models on a branch and open a PR
- **Did:** two commits on `scaffold-bronze-layer` (docs, then scaffold); PR #1 with What / Why / Testing
- **Checked:** `dbt parse` clean before committing; commits use the personal identity; `notes/` stayed out

### 9. Whiteboard: business flow and dimensional model

- **Asked:** before building, sketch the business flow to the revenue answer and a rough dimensional model; brainstorm only, no file changes
- **Did:** drew the employer → program → fee line → episode / adjustment flow, a star schema around shared conformed dims and two facts, and bronze → silver → gold lineage with one thin aggregate per question
- **Checked:** grains and joins match the raw-data profiling and the brief's business rules; the open design choice (memo-level adjustment fact) was left for me to decide

### 10. Silver and gold models for 2a

- **Asked:** build the models agreed in the brainstorm; tests and a memo-level fact deferred
- **Did:** recorded the modelling decisions before building (now in the model docs); built 5 silver staging models, 4 gold dims, 2 gold facts and the employer × month revenue aggregate, with descriptions and grain tests; asked me to settle one conflict (late-posted memos) rather than pick
- **Checked:** `dbt build` and `dbt docs generate` pass on a scratch database; ran each build-plan check and reconciled case revenue, the aggregate and platform-fee months against independent queries

### 11. Unit tests for business rules

- **Asked:** dbt unit tests (mocked inputs) for every business rule and data-issue fix built so far, without changing model SQL
- **Did:** added unit tests to the silver and gold yml, one rule each with edge cases (as-of boundaries, inclusive fee windows, partial months, exclusion precedence); left rules the brief and docs don't settle as open questions instead of encoding a guess
- **Checked:** `dbt build` passes; mutation-checked every test (broke the covered logic, confirmed the test failed, restored the SQL)

### 12. Blind re-derivation of Part 2 and the missing surgery date rule

- **Asked:** two independent agents, given only the brief and the CSVs, to answer 2a and 2b in plain SQL, then compare their results with the gold marts
- **Did:** every 2a difference traced to a documented choice, not a bug; all three agents reported completed episodes with no surgery date in their invoice month, and I agreed to switch from excluding them to that fallback, flagged in a new column
- **Checked:** `dbt build` and `dbt docs generate` pass; the new unit test was mutation-checked; with the same choices, gold matches an agent's result for every employer and month to the cent

### 13. Part 2a answer query and export

- **Asked:** build the saved 2a query and its CSV output
- **Did:** added a dbt analysis that only filters and totals the employer × month mart (month rows, employer Q2 totals, grand total), and a script that exports every compiled analysis to `outputs/`; documented the run steps in the README
- **Checked:** grand total matches the figure verified after the surgery-date fallback; subtotals are produced by the same query as the month rows; ran from a scratch build because the DuckDB UI held the lock

### 14. Relationship tests, error/warn policy and singular tests

- **Asked:** proceed with the deferred test layer
- **Did:** added relationship, accepted-values and not-null tests to silver and gold under a stated error/warn policy (warn only for orphans the model already handles); added four reconciliation tests and one discount invariant as singular tests; left the open edge-case questions untested
- **Checked:** `dbt build` passes with only the expected warnings; mutated a copy of the built database once per failure mode and confirmed each singular test caught it, then confirmed all return nothing on the real data

### 15. Test trim

- **Asked:** whether the tests hold value or are padding; then trim and log
- **Did:** removed tests that repeated a defect already warned elsewhere, could not fail by construction, covered columns no rule reads, or restated a model's own SQL; each known defect now warns once, at the first layer where it is visible
- **Checked:** `dbt build` passes with one warning per distinct defect; kept every unit test and the reconciliation tests that were mutation-checked

### 16. README trim

- **Asked:** make the README lean, each section minimally worded
- **Did:** cut it to setup, layers, test policy and Part 2 commands; grain and rules now point to the model docs instead of being repeated
- **Checked:** every command kept is one the build and export actually use

### 17. Part 2b utilization risk

- **Asked:** brainstorm 2b, then build it with the recommended decisions, recorded with what we saw and why
- **Did:** added a pacing model at fee-line grain (expected, completed, ratio, revenue at risk, flags) and the 2b answer query; escalation thresholds sit in the query because they are judgement, not definition
- **Checked:** build passes; the new unit test failed under each of four deliberate breaks of the model; the escalation list matches the reasoning in the brainstorm

### 18. Docs de-duplication

- **Asked:** whether the yml was getting bloated, then clean up
- **Did:** rules now live once, in the yml; SQL headers reduced to the grain line; unit tests moved to their own files; the two longest descriptions cut to what and how, with the why kept in my notes
- **Checked:** build and docs generate unchanged; both answer CSVs regenerate identically

### 19. Part 2c data quality register

- **Asked:** build gold model for one row per issue
- **Did:** added a gold report model with one row per issue: counts and dollar impacts computed from the models on every build, hand-written text for detection, handling, test and where the fix belongs; added the 2c answer query
- **Checked:** spot-checked the larger impacts against the earlier profiling and broke one down independently until it tied to the cent; the computed figure exposed an error in my own earlier pacing estimate, now corrected in my notes

### 20. Part 3 approach

- **Asked:** to follow a metric-view convention directed to (named dimensions and measures, each with a definition), with an LLM reading only aggregate tables
- **Did:** proposed definitions on the aggregate tables, comments written into the database, and one routing file
- **Checked:** read the brief's Part 3 wording and the metric-view example I pointed to before proposing

### 21. LLM-facing layer

- **Asked:** build it, including a program-level revenue table and moving the escalation rule into the pacing model
- **Did:** added program × month revenue and made the employer table a roll-up of it; moved the escalation rule into the pacing model; marked dimensions and measures on the four LLM-facing tables; wrote descriptions into DuckDB as comments; added AGENTS.md with routing, rules and what the data cannot answer
- **Checked:** the 2a and 2b outputs are unchanged; the program table sums to the same Q2 total; the new tests failed under deliberate breaks; fixed a list-ordering flaw that made the 2c output differ between builds

### 22. Full definitions on the LLM-facing tables

- **Asked:** whether the definitions were actually missing in the database
- **Did:** found 20 columns on three LLM-facing tables with no definition; documented them and added a test that fails if any column on those tables lacks a comment in the database
- **Checked:** every column on the four tables now has a comment in DuckDB; removing one description made the new test fail

### 23. Part 3 eval harness

- **Asked:** a repeatable eval: headless Claude Code on a fresh clone, generic instruction, read-only tools, graded against the marts
- **Did:** added `eval/` (questions, run script, grader)
- **Checked:** every question passed; hand-checked two answers to the cent; transcripts showed some runs never queried the database

### 24. Fixes from the eval

- **Asked:** fix the gaps the eval found, in the project, not the instruction
- **Did:** AGENTS.md shows the read-only query command; the register names the employer behind each flagged memo
- **Checked:** build passes; only the 2c output changed, and its memos tie to the 2a adjustments
