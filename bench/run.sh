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
#   --check                  Run preflight checks only and exit
#   --judge                  Run judge.py for every populated topic dir under bench/runs/<date>
#   --report                 Aggregate judge.json files into results.json and render report.md
#   --all                    Equivalent to --judge then --report
#   --topic <id>             Restrict judge/report to one topic
#   --force                  Re-run judge even when judge.json exists
#   --judge-model            Default: claude-sonnet-4-6
#   --swap-candidates <s>    Swap agents/<name>.md with candidate path. <s> is space-separated
#                            "name:path" pairs. Backs up originals to .bench-restore/<name>.md
#                            and writes a manifest to .bench-restore/_specs.txt. Refuses if a
#                            previous swap was not restored.
#   --restore-candidates     Restore agent files from .bench-restore/. Idempotent.
#
# NOTE on --judge: this dispatches judge.py which shells out to `claude -p`.
# That subprocess hits subscription rate limits independently from the parent
# Claude Code session and has historically failed with "credit balance too low".
# Inside Claude Code, prefer the /bench slash command (commands/bench.md
# Stage 4) which judges via Agent tool dispatch in-session. Use --judge here
# only in raw-CLI environments (e.g., scripted runs with $ANTHROPIC_API_KEY).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${BENCH_REPO_ROOT_OVERRIDE:-$(cd "$ROOT/.." && pwd)}"
TOPICS="$REPO_ROOT/bench/topics.yaml"
DATE="$(date -u +%Y-%m-%d)"
RUNS_DIR="$REPO_ROOT/bench/runs/$DATE"

RESTORE_DIR="$REPO_ROOT/.bench-restore"

JUDGE_MODEL="claude-sonnet-4-6"
ONLY_TOPIC=""
FORCE=0
DO_CHECK=0
DO_JUDGE=0
DO_REPORT=0
SWAP_SPECS=""
DO_RESTORE=0

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

candidates_swap() {
  if [[ -e "$RESTORE_DIR/_specs.txt" ]]; then
    echo "✗ $RESTORE_DIR/_specs.txt exists — previous swap not restored. Run --restore-candidates first." >&2
    return 1
  fi
  mkdir -p "$RESTORE_DIR"
  : > "$RESTORE_DIR/_specs.txt"
  for spec in $SWAP_SPECS; do
    local name="${spec%%:*}"
    local path="${spec#*:}"
    local agent_file="$REPO_ROOT/agents/${name}.md"
    if [[ ! -f "$agent_file" ]]; then
      echo "✗ agent file missing: $agent_file" >&2
      candidates_restore || true
      return 1
    fi
    if [[ ! -f "$path" ]]; then
      echo "✗ candidate path missing: $path" >&2
      candidates_restore || true
      return 1
    fi
    cp "$agent_file" "$RESTORE_DIR/${name}.md"
    cp "$path" "$agent_file"
    echo "$spec" >> "$RESTORE_DIR/_specs.txt"
    echo "✓ swapped agents/${name}.md ← $path"
  done
}

candidates_restore() {
  if [[ ! -d "$RESTORE_DIR" ]]; then
    echo "no $RESTORE_DIR — nothing to restore"
    return 0
  fi
  shopt -s nullglob
  for backup in "$RESTORE_DIR"/*.md; do
    local fname; fname=$(basename "$backup")
    local name="${fname%.md}"
    mv "$backup" "$REPO_ROOT/agents/${name}.md"
    echo "✓ restored agents/${name}.md"
  done
  shopt -u nullglob
  rm -f "$RESTORE_DIR/_specs.txt"
  rmdir "$RESTORE_DIR" 2>/dev/null || true
}

aggregate_and_report() {
  [[ -d "$RUNS_DIR" ]] || { echo "no $RUNS_DIR — nothing to aggregate" >&2; return 1; }

  local results="$RUNS_DIR/results.json"
  local categories_json
  categories_json=$(yq -o=json '.topics' "$TOPICS" | jq 'map({(.id): .category}) | add')

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
    --swap-candidates) SWAP_SPECS="$2"; shift 2 ;;
    --restore-candidates) DO_RESTORE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if (( ! DO_CHECK && ! DO_JUDGE && ! DO_REPORT && ! DO_RESTORE )) && [[ -z "$SWAP_SPECS" ]]; then
  echo "no stage selected — pass --check, --judge, --report, --all, --swap-candidates, or --restore-candidates" >&2
  echo "(run matrix is orchestrated by /bench slash command, not this script)" >&2
  exit 2
fi

if (( DO_CHECK )); then preflight || exit $?; fi
if [[ -n "$SWAP_SPECS" ]]; then candidates_swap || exit $?; fi
if (( DO_JUDGE )); then judge_all; fi
if (( DO_REPORT )); then aggregate_and_report; fi
if (( DO_RESTORE )); then candidates_restore; fi
