#!/usr/bin/env bash
# bench/post_research_bookkeeping.sh — single-call bookkeeping for RE-mode bench runs.
#
# Subagents previously had to chain: snapshot → /research → diff snapshots →
# locate new session → cp README → collect_metrics. Several subagents skipped
# the tail (cp + metrics), corrupting the matrix. This script collapses the
# tail into one call so the subagent prompt only needs:
#
#   1. snapshot via:  ls /home/taejin/projects/research-engine/research/ | sort > /tmp/before-<tag>.txt
#   2. invoke Skill('research-engine:research', ...)
#   3. bash post_research_bookkeeping.sh <bench_run_dir> <snapshot_file>
#
# The bench_run_dir is the destination (e.g., bench/runs/<date>/<topic>/re/run1).
# Exits non-zero if the new session can't be located or copy fails.
set -euo pipefail

BENCH_RUN_DIR="${1:?bench_run_dir required (e.g., bench/runs/<date>/<topic>/re/run1)}"
SNAPSHOT="${2:?snapshot_file required (created before Skill invocation)}"
RESEARCH_ROOT="${RESEARCH_ROOT:-/home/taejin/projects/research-engine/research}"

if [[ ! -f "$SNAPSHOT" ]]; then
  echo "✗ snapshot file missing: $SNAPSHOT" >&2
  exit 2
fi

mkdir -p "$BENCH_RUN_DIR"

# Diff the current research/ against the snapshot to find the new session(s).
# Take the most recent (last sorted) — handles slug-collision -2/-3 suffix.
NEW=$(ls "$RESEARCH_ROOT" 2>/dev/null | sort | comm -23 - "$SNAPSHOT" | tail -1)

if [[ -z "$NEW" || ! -d "$RESEARCH_ROOT/$NEW" ]]; then
  echo "✗ no new research session detected after snapshot" >&2
  echo '{"status":"failed","exit_code":1,"reason":"no_new_session"}' > "$BENCH_RUN_DIR/meta.json"
  exit 3
fi

if [[ ! -f "$RESEARCH_ROOT/$NEW/README.md" ]]; then
  echo "✗ new session $NEW exists but README.md is missing" >&2
  echo '{"status":"failed","exit_code":1,"reason":"no_readme"}' > "$BENCH_RUN_DIR/meta.json"
  exit 4
fi

cp "$RESEARCH_ROOT/$NEW/README.md" "$BENCH_RUN_DIR/output.md"

T=$(date +%s)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/collect_metrics.sh" "$BENCH_RUN_DIR" "$T" "$T"

echo "✓ bookkeeping complete: $NEW → $BENCH_RUN_DIR"
echo "  meta:"
cat "$BENCH_RUN_DIR/meta.json"
