# CLAUDE.md

Carrum Health Staff Analytics Engineer take-home: dbt Core + DuckDB over five CSV extracts.
Spec: [docs/ASSIGNMENT.md](docs/ASSIGNMENT.md) (transcribed from the .docx in the same folder; the .docx is the original).

## Environment

- Python 3.11 venv at `.venv`; versions pinned in `requirements.txt`.
- `profiles.yml` is in the repo root; the build writes `carrum.duckdb` there (override with `DBT_DUCKDB_PATH`).

```bash
source .venv/bin/activate
export DBT_PROFILES_DIR=.
dbt debug
dbt build
dbt docs generate
duckdb carrum.duckdb        # interactive SQL
```

## Raw data and as-of date

- Treat `data/*.csv` as read-only. Never edit, re-save or reorder them. Load them only through dbt.
- The as-of date is 2026-06-30. Read it from `var('as_of_date')`. Never hard-code it or use `current_date`.

## Working rules

- Every number that appears in an output or the write-up comes from a query saved in the repo. Don't quote ad-hoc results.
- The README must run from a clean clone. Update it in the same change as anything it depends on.
- Log each AI-assisted step in `docs/AI_LOG.md` (asked / did / checked): one short line each, no counts, IDs or lists that live elsewhere in the repo. Put the detail and decisions behind each entry in `notes/DECISIONS.md` (gitignored, personal).
- Write down an assumption before code relies on it.
- PR descriptions use three sections, a few lines each:
  - `## What`: the change, in one or two sentences; name the models touched.
  - `## Why`: the business or technical reason; cite the brief or a CLAUDE.md rule where one applies.
  - `## Testing`: the commands run and their results (`dbt build` pass/warn/error counts, row counts, before/after numbers).
  Add a table or lineage diagram only when it makes the change clearer.
- When you find a data anomaly, stop and report it with counts. Don't silently clean it.

## Medallion structure (always follow)

Every model belongs to one layer; schema = layer.

| Layer | Brief's term | Folder | Name → alias | Materialized |
|---|---|---|---|---|
| bronze | — | `models/bronze/` | `bronze_<file>` → `<file>` | view |
| silver | staging | `models/silver/stg/` | `silver_stg_<file>` → `stg_<file>` | table |
| silver | intermediate | `models/silver/int/` | `silver_int_<name>` → `int_<name>` | table |
| gold | marts | `models/gold/` | `gold_<dim\|fact\|agg\|rpt>_<name>` → `<dim\|fact\|agg\|rpt>_<name>` | table |

- **Bronze:** `select *` from `source('raw_sources', …)`. No cleaning, no dedup. Enforced contract + tests: error if silver would break, warn (with known count) for handled defects.
- **Silver:** objectively correct only: cast, parse, trim, exact dedup. One row per source record. Flag, don't filter.
- **Gold:** business rules and anything debatable. Aggregates put the grain in the name. State the grain of every model.
- **Grain test:** if it collapses rows, it's gold.
- Read only the layer directly below; never skip or read up. `ref()` the full model name.
- Answer queries (Part 2, Part 3) read gold only.
- `int_` only when a model is reused; otherwise use CTEs.
- Custom generic tests: `tests/generic/`.

## Decisions

Structural (implemented):
- Schemas are `bronze` / `silver` / `gold`; the brief's terms survive as the `stg_` / `int_` prefixes.
- Bronze is identical to the source; exact duplicates are removed in silver, not bronze.
- Silver and gold are tables so the DuckDB file can be queried from any directory (bronze views read the CSVs by relative path).
- Source name is `raw_sources`.

Modelling (proposed, to confirm before silver/gold are built):
- Episode status: latest record on or before `as_of_date`; rows after it are excluded from current status.
- NetSuite memos posted after `as_of_date` for in-period billing months: included and flagged.
- Null surgery dates: excluded from monthly revenue and flagged (no fallback to `invoice_month`).
- Episodes billed to a platform-fee line (FEE-403): excluded and flagged, not remapped.
- Employer roll-up: to the ultimate parent account; accounts whose parent does not exist are top level.
- A gold data-quality register model backs the 2c answer.
