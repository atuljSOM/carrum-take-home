"""Ask each eval question with headless Claude Code, then grade against the marts.

Called by eval/run.sh after it has cloned and built the repo. Not part of the dbt project.

    python eval.py --clone DIR --db DIR/carrum.duckdb --questions questions.yml --out results/X.md
"""

import argparse
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from decimal import Decimal
from pathlib import Path

import duckdb
import yaml

# The only instruction, identical for every question. No business rules or hints.
INSTRUCTION = "Answer using this repo and carrum.duckdb. Show the SQL you ran."

CLAUDE_ARGS = [
    "--tools", "Read,Grep,Glob,Bash",
    "--allowedTools", "Read", "Grep", "Glob", "Bash(duckdb -readonly:*)",
    "--permission-mode", "dontAsk",      # anything not allowed above is denied, never prompted
    "--strict-mcp-config",               # no MCP servers
    "--setting-sources", "project",      # ignore user settings in the config dir
    "--no-session-persistence",
    "--output-format", "stream-json", "--verbose",
]

NUM_TOL = 0.005  # relative
NUMBER_RE = re.compile(
    r"\d[\d,]*(?:\.\d+)?\s*(?:million|thousand|mm\b|m\b|k\b)?", re.IGNORECASE
)
DECLINE_RE = re.compile(
    r"(can(?:not|'t|’t)|unable to|not able to|no way to|isn't possible|is not possible)"
    r"[^.]{0,80}?\b(answer|determine|calculate|compute|tell|say|provide|forecast|project|"
    r"estimate|identify|know|measure|report)"
    r"|not answerable|cannot be answered|can't be answered|outside (?:the|what)"
    r"|(?:doesn't|does not|don't|do not|isn't|is not|aren't|are not)\s+(?:have|contain|include|"
    r"exist|available|exposed|in the)",
    re.IGNORECASE,
)


# ------------------------------------------------------------------ asking
def ask(q, clone, transcript_dir, model):
    prompt = f"{INSTRUCTION}\n\n{q['question'].strip()}"
    cmd = ["claude", "-p", prompt, *CLAUDE_ARGS] + (["--model", model] if model else [])
    path = transcript_dir / f"{q['id']}.jsonl"
    with open(path, "w") as f:
        proc = subprocess.run(cmd, cwd=clone, stdout=f, stderr=subprocess.PIPE, text=True)
    sanitize(path)
    res = parse_transcript(path)
    if proc.returncode != 0 or res["is_error"]:
        res["error"] = (proc.stderr.strip() or res["answer"] or f"exit {proc.returncode}")[:300]
        print(f"  {q['id']}: claude failed: {res['error']}", file=sys.stderr)
    return res


INIT_KEEP = ("type", "subtype", "model", "tools", "mcp_servers", "permissionMode", "claude_code_version")


def sanitize(path):
    """Transcripts are committed: keep only the run settings from the init event, hide $HOME."""
    home = os.path.expanduser("~")
    out = []
    for line in path.read_text().splitlines():
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if ev.get("type") == "system" and ev.get("subtype") == "init":
            ev = {k: ev[k] for k in INIT_KEEP if k in ev}
        out.append(json.dumps(ev).replace(home, "~"))
    path.write_text("\n".join(out) + "\n")


def parse_transcript(path):
    answer, queries, pending, is_error = "", [], {}, False
    for line in path.read_text().splitlines():
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        message = ev.get("message")
        content = (message.get("content") if isinstance(message, dict) else None) or []
        if ev.get("type") == "assistant":
            for c in content:
                if c.get("type") == "tool_use" and c.get("name") == "Bash":
                    pending[c["id"]] = c["input"].get("command", "")
        elif ev.get("type") == "user":
            for c in content if isinstance(content, list) else []:
                if c.get("type") == "tool_result" and c.get("tool_use_id") in pending:
                    queries.append({"command": pending.pop(c["tool_use_id"]),
                                    "denied_or_failed": bool(c.get("is_error"))})
        elif ev.get("type") == "result":
            answer = ev.get("result") or ""
            is_error = bool(ev.get("is_error"))
    queries += [{"command": cmd, "denied_or_failed": None} for cmd in pending.values()]
    return {"answer": answer, "queries": queries, "is_error": is_error, "error": ""}


# ------------------------------------------------------------------ grading
def expected_cells(con, sql):
    cells = []
    for stmt in [s for s in sql.split(";") if s.strip()]:
        for row in con.execute(stmt).fetchall():
            cells += [v for v in row if v is not None]
    return cells


def numbers_in(text):
    out = []
    for m in NUMBER_RE.finditer(text):
        raw = m.group(0).lower().replace(",", "").strip()
        scale = 1
        for suffix, s in (("million", 1e6), ("thousand", 1e3), ("mm", 1e6), ("m", 1e6), ("k", 1e3)):
            if raw.endswith(suffix):
                raw, scale = raw[: -len(suffix)].strip(), s
                break
        try:
            out.append(float(raw) * scale)
        except ValueError:
            pass
    return out


def found(cell, text, nums):
    if isinstance(cell, (int, float, Decimal)) and not isinstance(cell, bool):
        target = abs(float(cell))
        return any(abs(n - target) <= max(NUM_TOL * target, 0.005) for n in nums)
    return str(cell).lower() in text.lower()


def grade(q, result, con):
    if result.get("error"):
        return "error", "claude run failed: " + result["error"].replace("\n", " ")[:120]
    answer = result["answer"]
    declined = bool(DECLINE_RE.search(answer))
    if q["expected"] == "decline":
        # A refusal that still quotes a confident estimate is not a decline.
        return ("declined", "") if declined else ("wrong", "answered instead of declining")
    cells = expected_cells(con, q["expected"]["sql"])
    nums = numbers_in(answer)
    missing = [c for c in cells if not found(c, answer, nums)]
    if not missing:
        return "right", ""
    if declined and len(missing) == len(cells):
        return "declined", ""
    return "wrong", "missing: " + ", ".join(fmt(c) for c in missing)


def fmt(v):
    if isinstance(v, Decimal):
        return f"{v:,.2f}"
    if isinstance(v, float):
        return f"{v:,.4g}"
    return str(v)


# ------------------------------------------------------------------ report
def report(rows, meta):
    passed = sum(r["pass"] for r in rows)
    lines = [
        f"# Part 3 eval: {meta['date']}", "",
        f"- Commit: `{meta['commit']}` ({meta['branch']}), fresh clone, `dbt build`: {meta['build']}",
        f"- Model: {meta['model'] or 'Claude Code default'}",
        f"- Instruction (every question): \"{INSTRUCTION}\"",
        "- Tools: Read, Grep, Glob, Bash limited to `duckdb -readonly`",
        f"- Score: **{passed} / {len(rows)}** (right on answerable questions, declined on unanswerable)",
        "- Grades are automatic (numbers within 0.5%, text as substring, declines by phrase). "
        "Hand-check before quoting them.", "",
        "| id | type | grade | pass | note |", "|---|---|---|---|---|",
    ]
    for r in rows:
        lines.append(f"| {r['id']} | {r['type']} | {r['grade']} | {'✅' if r['pass'] else '❌'} | {r['note']} |")
    for r in rows:
        sql = "\n\n".join(
            q["command"] + ("\n-- (denied or failed)" if q["denied_or_failed"] else "") for q in r["queries"]
        ) or "(none)"
        lines += [
            "", "---", "", f"## {r['id']} ({r['type']}): {r['grade']}", "",
            f"**Question.** {r['question'].strip()}", "",
            f"**Expected.** {r['expected']}", "",
            "**Answer.**", "", r["answer"].strip() or "(empty)", "",
            "<details><summary>SQL / commands the model ran</summary>", "", "```", sql, "```", "", "</details>",
        ]
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clone", required=True, type=Path)
    ap.add_argument("--db", required=True)
    ap.add_argument("--questions", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--transcripts", required=True, type=Path)
    ap.add_argument("--only", default="")
    ap.add_argument("--parallel", type=int, default=3)
    ap.add_argument("--model", default=os.environ.get("EVAL_MODEL", ""))
    ap.add_argument("--commit", default="")
    ap.add_argument("--branch", default="")
    ap.add_argument("--build", default="")
    args = ap.parse_args()

    qs = yaml.safe_load(args.questions.read_text())["questions"]
    if args.only:
        keep = set(args.only.split(","))
        qs = [q for q in qs if q["id"] in keep]
    args.transcripts.mkdir(parents=True, exist_ok=True)

    with ThreadPoolExecutor(max_workers=args.parallel) as pool:
        results = list(pool.map(lambda q: ask(q, args.clone, args.transcripts, args.model), qs))

    con = duckdb.connect(args.db, read_only=True)
    rows = []
    for q, res in zip(qs, results):
        g, note = grade(q, res, con)
        if q["expected"] == "decline":
            expected = "decline"
        else:
            expected = ", ".join(fmt(c) for c in expected_cells(con, q["expected"]["sql"]))
        ok = g == ("declined" if q["expected"] == "decline" else "right")
        rows.append({**q, **res, "grade": g, "note": note, "pass": ok, "expected": expected})
        print(f"  {q['id']:5} {g:9} {note}")

    meta = {"date": date.today().isoformat(), "commit": args.commit, "branch": args.branch,
            "build": args.build, "model": args.model}
    args.out.write_text(report(rows, meta))
    print(f"Score {sum(r['pass'] for r in rows)}/{len(rows)} -> {args.out}")


if __name__ == "__main__":
    main()
