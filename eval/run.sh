#!/usr/bin/env bash
# Part 3 eval: fresh clone -> README setup + dbt build -> ask headless Claude Code each question
# in eval/questions.yml -> grade against the marts -> eval/results/<date>.md.
#
#   eval/run.sh                 # all questions
#   eval/run.sh vp1,na2         # a subset
#
# Env overrides:
#   EVAL_CLAUDE_CONFIG_DIR  Claude Code config dir (default ~/.claude-personal; log in there once)
#   EVAL_REPO / EVAL_BRANCH  what to clone (default: this repo, current branch; committed work only)
#   EVAL_MODEL              model for `claude -p` (default: Claude Code's default)
#   EVAL_PARALLEL           questions asked at once (default 3)
#   EVAL_KEEP=1             keep the temp clone
set -euo pipefail

EVAL_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$EVAL_DIR/.." && pwd)"
REPO="${EVAL_REPO:-$REPO_ROOT}"
BRANCH="${EVAL_BRANCH:-$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)}"
export CLAUDE_CONFIG_DIR="${EVAL_CLAUDE_CONFIG_DIR:-$HOME/.claude-personal}"
ONLY="${1:-}"

if [ ! -d "$CLAUDE_CONFIG_DIR" ]; then
  echo "No Claude config at $CLAUDE_CONFIG_DIR. Log in once with your personal account:" >&2
  echo "  CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR claude   # then /login" >&2
  exit 1
fi
if [ -n "$(git -C "$REPO_ROOT" status --porcelain -- . ':!eval')" ]; then
  echo "Note: uncommitted changes are not in the clone; the eval runs on committed $BRANCH." >&2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/carrum-eval.XXXXXX")"
CLONE="$WORK/carrum-take-home"
[ "${EVAL_KEEP:-0}" = 1 ] || trap 'rm -rf "$WORK"' EXIT

STAMP="$(date +%F)"
OUT="$EVAL_DIR/results/$STAMP.md"
[ -e "$OUT" ] && STAMP="$(date +%F-%H%M)" && OUT="$EVAL_DIR/results/$STAMP.md"
TRANSCRIPTS="$EVAL_DIR/results/$STAMP"
mkdir -p "$TRANSCRIPTS"

echo "== clone $REPO ($BRANCH) -> $CLONE"
case "$REPO" in /*) SRC="file://$REPO" ;; *) SRC="$REPO" ;; esac
git clone --quiet --depth 1 --branch "$BRANCH" "$SRC" "$CLONE"
COMMIT="$(git -C "$CLONE" rev-parse --short HEAD)"

echo "== setup and dbt build (README steps)"
(
  cd "$CLONE"
  python3.11 -m venv .venv
  .venv/bin/pip install --quiet -r requirements.txt pyyaml
  DBT_PROFILES_DIR=. .venv/bin/dbt build > "$TRANSCRIPTS/dbt_build.log" 2>&1
) || { echo "dbt build failed; see $TRANSCRIPTS/dbt_build.log" >&2; exit 1; }
BUILD="$(grep -o 'PASS=[0-9]* WARN=[0-9]* ERROR=[0-9]*' "$TRANSCRIPTS/dbt_build.log" | tail -1)"
echo "   $BUILD"

# The model under test must not read the questions or expected answers.
rm -rf "$CLONE/eval"

echo "== ask and grade"
"$CLONE/.venv/bin/python" "$EVAL_DIR/eval.py" \
  --clone "$CLONE" --db "$CLONE/carrum.duckdb" \
  --questions "$EVAL_DIR/questions.yml" --out "$OUT" --transcripts "$TRANSCRIPTS" \
  --only "$ONLY" --parallel "${EVAL_PARALLEL:-3}" \
  --commit "$COMMIT" --branch "$BRANCH" --build "$BUILD"
