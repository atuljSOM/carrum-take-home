# Carrum Health — Staff Analytics Engineer Take-Home

dbt Core + DuckDB over Salesforce, contracting, care-platform and NetSuite extracts.

## Setup (macOS, clean clone)

```bash
git clone <repo-url> carrum-take-home && cd carrum-take-home
python3.11 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export DBT_PROFILES_DIR=.
dbt build
```

Writes `carrum.duckdb` in the repo root. Close other DuckDB sessions on it first (single writer).

## Layers

| Schema | Brief's term | Holds |
|---|---|---|
| `bronze` | — | Exact copy of each CSV + data contract |
| `silver` | staging | Typed, cleaned, one row per source record |
| `gold` | marts | Business rules. **Query this schema only.** |

Grain and rules: see each model's description in `models/**/_*.yml`.

## Tests

- **Error:** would silently change a number (grain, unknown category, broken key, reconciliation).
- **Warn:** known defect the models handle. Expect 10; each states its count.
- Unit tests: `dbt test --select "test_type:unit"`.

## Part 2 answers

```bash
dbt compile --select "resource_type:analysis"
python scripts/export_answers.py      # writes outputs/<analysis>.csv
```

| Question | Query | Output |
|---|---|---|
| 2a | `analyses/q2a_revenue_by_employer_q2_2026.sql` | `outputs/q2a_revenue_by_employer_q2_2026.csv` |
