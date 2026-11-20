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

- **Asked:** three independent agents, given only the brief and the CSVs, to answer 2a and 2b in plain SQL, then compare their results with the gold marts
- **Did:** every 2a difference traced to a documented choice, not a bug; all three agents reported completed episodes with no surgery date in their invoice month, and I agreed to switch from excluding them to that fallback, flagged in a new column
- **Checked:** `dbt build` and `dbt docs generate` pass; the new unit test was mutation-checked; with the same choices, gold matches an agent's result for every employer and month to the cent
