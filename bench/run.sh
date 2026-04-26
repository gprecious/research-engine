#!/usr/bin/env bash
# bench/run.sh — research-engine vs baseline mini-bench utility helpers.
#
# The run matrix itself (per-topic × per-mode × per-N execution) lives in
# commands/bench.md and is orchestrated by Claude inside the user's session,
# because `claude -p` does not invoke plugin slash commands non-interactively.
# This script handles the non-runtime stages: preflight, judge dispatch,
# aggregation, and report rendering.
#
# Flags:
#   --check        Run preflight checks only and exit
#   --judge        Run judge.py for every populated topic dir under bench/runs/<date>
#   --report       Aggregate judge.json files into results.json and render report.md
#   --all          Equivalent to --judge then --report
#   --topic <id>   Restrict judge/report to one topic
#   --force        Re-run judge even when judge.json exists
#   --judge-model  Default: claude-sonnet-4-6
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${BENCH_REPO_ROOT_OVERRIDE:-$(cd "$ROOT/.." && pwd)}"
TOPICS="$REPO_ROOT/bench/topics.yaml"
DATE="$(date -u +%Y-%m-%d)"
RUNS_DIR="$REPO_ROOT/bench/runs/$DATE"

JUDGE_MODEL="claude-sonnet-4-6"
ONLY_TOPIC=""
FORCE=0
DO_CHECK=0
DO_JUDGE=0
DO_REPORT=0

usage() { sed -n '2,/^set/p' "$0" | sed 's/^# \{0,1\}//;s/^set.*//' | head -20; }

preflight() {
  local errors=0
  for cmd in claude yq jq python3; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "✓ $cmd present"
    else
      echo "✗ $cmd MISSING" >&2
      errors=$((errors+1))
    fi
  done

  if [[ -n "${NOTION_TOKEN:-}" ]]; then
    echo "✗ NOTION_TOKEN is set — bench refuses to run with Notion credentials in env (would risk push)" >&2
    errors=$((errors+1))
  else
    echo "✓ NOTION_TOKEN unset"
  fi

  if [[ ! -f "$TOPICS" ]]; then
    echo "✗ topics.yaml missing at $TOPICS" >&2
    errors=$((errors+1))
  else
    echo "✓ topics.yaml present"
    if ! yq '.topics[].id' "$TOPICS" >/dev/null 2>&1; then
      echo "✗ topics.yaml does not parse" >&2
      errors=$((errors+1))
    fi
  fi

  if (( errors > 0 )); then
    echo "Preflight FAILED ($errors error(s))" >&2
    return 1
  fi
  echo "Preflight OK"
}

judge_all() {
  [[ -d "$RUNS_DIR" ]] || { echo "no $RUNS_DIR — nothing to judge" >&2; return 1; }

  local topic_ids
  if [[ -n "$ONLY_TOPIC" ]]; then
    topic_ids="$ONLY_TOPIC"
  else
    topic_ids=$(yq -r '.topics[].id' "$TOPICS")
  fi

  for topic_id in $topic_ids; do
    local td="$RUNS_DIR/$topic_id"
    if [[ ! -d "$td/re" || ! -d "$td/baseline" ]]; then
      echo "  [judge $topic_id] skip (re or baseline missing)"
      continue
    fi
    if [[ -f "$td/judge.json" && "$FORCE" -ne 1 ]]; then
      echo "  [judge $topic_id] skip exists"
      continue
    fi
    python3 "$ROOT/judge.py" --topic-dir "$td" --topic-id "$topic_id" --judge-model "$JUDGE_MODEL" \
      || echo "  [judge $topic_id] FAILED — continuing"
  done
}

aggregate_and_report() {
  [[ -d "$RUNS_DIR" ]] || { echo "no $RUNS_DIR — nothing to aggregate" >&2; return 1; }

  local results="$RUNS_DIR/results.json"
  local categories_json
  categories_json=$(yq -o=json '.topics | map({(.id): .category}) | add' "$TOPICS")

  TOPIC_CATEGORIES="$categories_json" python3 - <<PY > "$results"
import json, os
from pathlib import Path
categories = json.loads(os.environ.get("TOPIC_CATEGORIES", "{}"))
runs_dir = Path("$RUNS_DIR")
topics = []
for td in sorted(p for p in runs_dir.iterdir() if p.is_dir()):
    judge_path = td / "judge.json"
    j = json.loads(judge_path.read_text()) if judge_path.exists() else {}
    cm = j.get("cross_mode", {})
    repro = j.get("reproducibility", {})

    def block(mode):
        scores = dict(cm.get(mode, {}))
        scores.pop("rationale", None)
        scores["reproducibility"] = repro.get(mode)
        nums = [v for v in scores.values() if isinstance(v, (int, float))]
        weighted = round(sum(nums) * 10 / (len(nums) or 1), 2) if nums else None
        return {"scores": scores, "weighted_total": weighted}

    re_b, base_b = block("re"), block("baseline")
    delta = (re_b["weighted_total"] or 0) - (base_b["weighted_total"] or 0) if (re_b["weighted_total"] and base_b["weighted_total"]) else None
    topics.append({
        "id": td.name, "category": categories.get(td.name, "?"),
        "re": re_b, "baseline": base_b, "delta": delta,
        "judge_rationale": (cm.get("re", {}).get("rationale", "") + " | " + cm.get("baseline", {}).get("rationale", "")).strip(" |"),
    })

def avg(xs):
    xs = [x for x in xs if x is not None]
    return round(sum(xs)/len(xs), 2) if xs else None
re_avg = avg([t["re"]["weighted_total"] for t in topics])
base_avg = avg([t["baseline"]["weighted_total"] for t in topics])
delta_avg = avg([t["delta"] for t in topics])
by_axis = {}
for axis in ("coverage","citation","depth","structure","reproducibility"):
    by_axis[axis] = {
        "re":       avg([t["re"]["scores"].get(axis) for t in topics]),
        "baseline": avg([t["baseline"]["scores"].get(axis) for t in topics]),
    }
print(json.dumps({
    "bench_date": "$DATE",
    "judge_model": "$JUDGE_MODEL",
    "model_under_test": os.environ.get("CLAUDE_MODEL", "default"),
    "topics": topics,
    "aggregate": {"re_avg": re_avg, "baseline_avg": base_avg, "delta_avg": delta_avg, "by_axis": by_axis, "by_category": {}},
}, indent=2, ensure_ascii=False))
PY

  python3 "$ROOT/report.py" --results "$results" --out "$RUNS_DIR/report.md"
  echo "✅ Report: $RUNS_DIR/report.md"
}

while (( $# > 0 )); do
  case "$1" in
    --check) DO_CHECK=1; shift ;;
    --judge) DO_JUDGE=1; shift ;;
    --report) DO_REPORT=1; shift ;;
    --all) DO_JUDGE=1; DO_REPORT=1; shift ;;
    --topic) ONLY_TOPIC="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --judge-model) JUDGE_MODEL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if (( ! DO_CHECK && ! DO_JUDGE && ! DO_REPORT )); then
  echo "no stage selected — pass --check, --judge, --report, or --all" >&2
  echo "(run matrix is orchestrated by /bench slash command, not this script)" >&2
  exit 2
fi

if (( DO_CHECK )); then preflight || exit $?; fi
if (( DO_JUDGE )); then judge_all; fi
if (( DO_REPORT )); then aggregate_and_report; fi
