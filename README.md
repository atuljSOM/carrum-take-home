# Carrum Health — Staff Analytics Engineer Take-Home

dbt Core + DuckDB project modelling Salesforce, contracting, care-platform and NetSuite extracts.

## Setup (macOS, from a clean clone)

```bash
git clone <repo-url> carrum-take-home && cd carrum-take-home
python3.11 -m venv .venv          # dbt supports Python 3.10–3.12
source .venv/bin/activate
pip install -r requirements.txt
export DBT_PROFILES_DIR=.         # profiles.yml lives in the repo
dbt debug
dbt build
```

The build writes `carrum.duckdb` in the repo root (override with `DBT_DUCKDB_PATH`). Close any other
DuckDB session on that file first (for example `duckdb -ui carrum.duckdb`); DuckDB allows only one writer.

## Project layout (medallion)

Data flows bronze → silver → gold. Each layer is a DuckDB schema and reads only the one below.

| Schema | Brief's term | Holds |
|---|---|---|
| `bronze` | — | Exact copy of each CSV, plus a data contract that fails on drift |
| `silver` | staging (`stg_`), intermediate (`int_`) | Typed and cleaned; one row per source record |
| `gold` | marts | Business rules, revenue and pacing. **Query this schema only.** |

### Expected warnings

There are 10, all intentional: known defects in the raw extracts, each with its count in
`models/bronze/_bronze.yml`. A changed count means the data changed. The "config paths match no
models" warning clears once silver and gold have models.

_Run instructions for Part 2 queries, Part 3 and docs to follow._
