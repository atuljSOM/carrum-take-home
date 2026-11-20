"""Run every dbt analysis against the built DuckDB file and save each result as a CSV.

Usage (from the repo root, after `dbt build`):
    dbt compile --select "resource_type:analysis"
    python scripts/export_answers.py

Reads the compiled SQL in target/compiled/carrum/analyses/ and writes outputs/<analysis>.csv.
Opens the database read-only; close any other DuckDB session that holds a write lock first.
"""

import os
import pathlib
import sys

import duckdb

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMPILED = ROOT / "target" / "compiled" / "carrum" / "analyses"
OUTPUTS = ROOT / "outputs"
DB_PATH = os.environ.get("DBT_DUCKDB_PATH", str(ROOT / "carrum.duckdb"))


def main() -> int:
    files = sorted(COMPILED.glob("*.sql"))
    if not files:
        print(f"No compiled analyses in {COMPILED}. Run `dbt compile --select \"resource_type:analysis\"` first.")
        return 1

    OUTPUTS.mkdir(exist_ok=True)
    con = duckdb.connect(DB_PATH, read_only=True)
    for sql_file in files:
        sql = sql_file.read_text().strip().rstrip(";")
        out = OUTPUTS / f"{sql_file.stem}.csv"
        con.execute(f"copy ({sql}) to '{out}' (header, delimiter ',')")
        rows = con.execute(f"select count(*) from read_csv('{out}')").fetchone()[0]
        print(f"{sql_file.stem}: {rows} rows -> {out.relative_to(ROOT)}")
    con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
