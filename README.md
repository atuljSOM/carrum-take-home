# Carrum Health — Staff Analytics Engineer Take-Home

dbt Core + DuckDB over Salesforce, contracting, care-platform and NetSuite extracts.
Asking questions of the built data (people or LLMs): see [AGENTS.md](AGENTS.md).

## Setup (macOS, clean clone)

```bash
git clone https://github.com/atuljSOM/carrum-take-home.git carrum-take-home && cd carrum-take-home
python3.11 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export DBT_PROFILES_DIR=.
dbt build
```

Writes `carrum.duckdb` in the repo root. Close other DuckDB sessions on it first (single writer).
Optional: the DuckDB CLI (`brew install duckdb`) for ad-hoc SQL and `duckdb < scripts/profile_raw_csvs.sql`
(the raw-data profiling); `AGENTS.md` also gives a Python fallback.

Docs: `dbt docs generate && dbt docs serve`.

**Why sources, not seeds.** The CSVs are dbt sources read in place (dbt-duckdb external location),
every column as text: the files are never copied or edited, and a malformed value reaches the
bronze contract as data to test instead of failing or being silently coerced at load.

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
| 2b | `analyses/q2b_utilization_risk.sql` | `outputs/q2b_utilization_risk.csv` |
| 2c | `analyses/q2c_data_quality_register.sql` | `outputs/q2c_data_quality_register.csv` |

## Part 3

- Questions about the data: [AGENTS.md](AGENTS.md) (four LLM-facing gold tables; definitions are also stored as comments in `carrum.duckdb`).
- Eval: `eval/run.sh` (headless Claude Code on a fresh clone; needs a Claude Code login). Results and transcripts: `eval/results/`.
- Write-up and Part 4: [findings.md](findings.md).

