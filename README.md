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

The build writes `carrum.duckdb` in the repo root (override with `DBT_DUCKDB_PATH`).

_Run instructions for Part 2 queries, Part 3 and docs to follow._
