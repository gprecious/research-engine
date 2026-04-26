#!/usr/bin/env bash
# bench/run.sh — research-engine vs baseline mini-bench runner.
# Spike-aligned: uses --disable-slash-commands for baseline plugin isolation
# and --output-format=json to capture token counts in raw.json.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${BENCH_REPO_ROOT_OVERRIDE:-$(cd "$ROOT/.." && pwd)}"
TOPICS="$REPO_ROOT/bench/topics.yaml"
DATE="$(date -u +%Y-%m-%d)"
RUNS_DIR="$REPO_ROOT/bench/runs/$DATE"

JUDGE_MODEL="claude-sonnet-4-6"
ONLY_TOPIC=""
ONLY_MODE=""
FORCE=0
NO_JUDGE=0
JUDGE_ONLY=0
REPORT_ONLY=0
TIMEOUT_S=1800

usage() {
  cat <<EOF
bench/run.sh — research-engine vs baseline mini-bench runner

  --check                Run preflight checks only and exit
  --topic <id>           Restrict to one topic
  --mode re|baseline     Restrict to one mode
  --force                Overwrite existing run outputs
  --no-judge             Skip judge stage
  --judge-only           Skip runs, only run judge
  --report-only          Skip runs + judge, only render report
  --judge-model <m>      Default: claude-sonnet-4-6
EOF
}

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

run_one() {
  local topic_id="$1" mode="$2" run_n="$3"
  local out_dir="$RUNS_DIR/$topic_id/$mode/run$run_n"
  mkdir -p "$out_dir"

  if [[ -s "$out_dir/output.md" && "$FORCE" -ne 1 ]]; then
    echo "  [skip exists] $topic_id/$mode/run$run_n"
    return 0
  fi

  local url topic_text prompt
  url=$(yq -r ".topics[] | select(.id==\"$topic_id\") | .url" "$TOPICS")
  topic_text="${topic_id#topic-}"

  if [[ "$mode" == "re" ]]; then
    if [[ "$url" == "null" || -z "$url" ]]; then
      prompt="/research \"$topic_text\" --fresh --yes"
    else
      prompt="/research $url --fresh --yes"
    fi
  else
    local raw
    raw=$(yq -r ".topics[] | select(.id==\"$topic_id\") | .baseline_prompt" "$TOPICS")
    if [[ "$url" == "null" || -z "$url" ]]; then
      prompt="${raw//\{topic\}/$topic_text}"
    else
      prompt="${raw//\{url\}/$url}"
    fi
  fi

  echo "  [$topic_id/$mode/run$run_n] starting"
  local start; start=$(date +%s)

  # Plugin isolation: baseline uses --disable-slash-commands so research-engine
  # slash commands aren't available to it.
  local extra_args=()
  if [[ "$mode" == "baseline" ]]; then
    extra_args+=(--disable-slash-commands)
  fi

  local exit_code=0
  env NOTION_TOKEN= \
    timeout "$TIMEOUT_S" \
    claude -p --output-format=json "${extra_args[@]}" "$prompt" \
    > "$out_dir/raw.json" 2> "$out_dir/stderr.log" \
    || exit_code=$?

  local end; end=$(date +%s)

  if (( exit_code == 124 )); then
    jq -n --argjson w $((end-start)) '{status:"timeout", wall_time_sec:$w, exit_code:124}' > "$out_dir/meta.json"
    echo "  [$topic_id/$mode/run$run_n] TIMEOUT"
    return 0
  elif (( exit_code != 0 )); then
    jq -n --argjson w $((end-start)) --argjson e "$exit_code" '{status:"failed", wall_time_sec:$w, exit_code:$e}' > "$out_dir/meta.json"
    echo "  [$topic_id/$mode/run$run_n] FAILED ($exit_code)"
    return 0
  fi

  # Derive output.md from raw.json (the .result field holds the markdown).
  if ! jq -er '.result' "$out_dir/raw.json" > "$out_dir/output.md" 2>/dev/null; then
    # raw.json missing .result — treat as failed
    jq -n --argjson w $((end-start)) '{status:"failed", wall_time_sec:$w, exit_code:0}' > "$out_dir/meta.json"
    echo "  [$topic_id/$mode/run$run_n] FAILED (no .result in JSON)"
    return 0
  fi

  "$ROOT/collect_metrics.sh" "$out_dir" "$start" "$end"
  echo "  [$topic_id/$mode/run$run_n] OK $((end-start))s"
}

main() {
  if (( ! REPORT_ONLY )); then
    preflight
  fi
  mkdir -p "$RUNS_DIR"

  local topic_ids
  if [[ -n "$ONLY_TOPIC" ]]; then
    topic_ids="$ONLY_TOPIC"
  else
    topic_ids=$(yq -r '.topics[].id' "$TOPICS")
  fi

  if (( ! REPORT_ONLY && ! JUDGE_ONLY )); then
    for topic_id in $topic_ids; do
      for mode in re baseline; do
        if [[ -n "$ONLY_MODE" && "$mode" != "$ONLY_MODE" ]]; then continue; fi
        for n in 1 2; do
          run_one "$topic_id" "$mode" "$n"
        done
      done
    done
  fi

  if (( ! NO_JUDGE && ! REPORT_ONLY )); then
    for topic_id in $topic_ids; do
      local td="$RUNS_DIR/$topic_id"
      if [[ ! -d "$td/re" || ! -d "$td/baseline" ]]; then continue; fi
      if [[ -f "$td/judge.json" && "$FORCE" -ne 1 ]]; then
        echo "  [judge $topic_id] skip exists"
        continue
      fi
      python3 "$ROOT/judge.py" --topic-dir "$td" --topic-id "$topic_id" --judge-model "$JUDGE_MODEL" \
        || echo "  [judge $topic_id] FAILED — continuing"
    done
  fi

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

  echo
  echo "✅ Bench complete. Report: $RUNS_DIR/report.md"
}

while (( $# > 0 )); do
  case "$1" in
    --check) preflight; exit $? ;;
    --topic) ONLY_TOPIC="$2"; shift 2 ;;
    --mode) ONLY_MODE="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --no-judge) NO_JUDGE=1; shift ;;
    --judge-only) JUDGE_ONLY=1; shift ;;
    --report-only) REPORT_ONLY=1; shift ;;
    --judge-model) JUDGE_MODEL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

main
