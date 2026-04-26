#!/usr/bin/env bash
# bench/run.sh — orchestrator. Phase 1: preflight only (Task 12).
# Full run matrix lands in Task 13.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${BENCH_REPO_ROOT_OVERRIDE:-$(cd "$ROOT/.." && pwd)}"
TOPICS="$REPO_ROOT/bench/topics.yaml"

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

CHECK_ONLY=0
case "${1:-}" in
  ""|--help|-h) usage; exit 0 ;;
  --check) CHECK_ONLY=1 ;;
esac

if (( CHECK_ONLY )); then
  preflight
  exit $?
fi

# Full run matrix is implemented in Task 13.
echo "TODO: full run matrix lands in Task 13" >&2
exit 2
