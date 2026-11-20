# CLAUDE.md

Carrum Health Staff Analytics Engineer take-home: dbt Core + DuckDB over five CSV extracts.
Spec: [docs/ASSIGNMENT.md](docs/ASSIGNMENT.md) (transcribed from the .docx in the same folder; the .docx is the original).

**Answering questions about the data (not building the project)? Follow [AGENTS.md](AGENTS.md) and ignore the rest of this file.**

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

- Numbers in `outputs/` and `findings.md` come from queries saved in the repo.
- The README must run from a clean clone. Update it in the same change as anything it depends on.
- Log each AI-assisted step in `docs/AI_LOG.md` (asked / did / checked): one short line each, no counts, IDs or lists that live elsewhere in the repo.
- Write down an assumption in the model's yml description before code relies on it.
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
- Unit tests: in the model's existing yml, under `unit_tests:`. One rule per test, fewest rows, edge cases (as-of date, window boundaries, nulls); pin `as_of_date` in `overrides`. Mutation-check each new test (break the logic, see it fail, revert). Don't encode a guess for a rule the brief or the model docs don't settle: ask.

## Decisions

- Silver and gold are tables, not views, so `carrum.duckdb` can be queried from any directory.
- Modelling decisions live in the model and column descriptions (`models/**/_*.yml`). Don't change one without asking.
