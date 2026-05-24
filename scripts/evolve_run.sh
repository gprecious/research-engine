#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   evolve_run.sh prepare  <adapter-name> <region-id>
#       → prints: { current_body, dream_excerpts, bench_weaknesses }
#   evolve_run.sh apply    <adapter-name> <region-id> <mutator-output.json>
#       → writes agents/<name>.candidate.md, prints candidate path
#   evolve_run.sh decide   <adapter-name> <bench-current.json> <bench-candidate.json>
#       → runs statistical_gate, updates ledger, prints decision
#   evolve_run.sh promote  <adapter-name>
#       → swaps candidate → live, archives previous (caller stages with git)

CMD=${1:-}
case "$CMD" in
  prepare|apply|decide|promote) ;;
  *) echo "usage: $0 {prepare|apply|decide|promote} ..." >&2; exit 64 ;;
esac

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LEDGER="$ROOT/research/_index/evolve-ledger.json"
AGENTS="$ROOT/agents"

case "$CMD" in
  prepare)
    NAME=${2:?"usage: $0 prepare <adapter-name> <region-id>"}
    REGION=${3:?"usage: $0 prepare <adapter-name> <region-id>"}
    node "$ROOT/lib/evolve/prepare.mjs" "$AGENTS/$NAME.md" "$REGION"
    ;;
  apply)
    NAME=${2:?"usage: $0 apply <adapter-name> <region-id> <mutator-output.json>"}
    REGION=${3:?"usage: $0 apply <adapter-name> <region-id> <mutator-output.json>"}
    MUT=${4:?"usage: $0 apply <adapter-name> <region-id> <mutator-output.json>"}
    node "$ROOT/lib/evolve/apply.mjs" "$AGENTS/$NAME.md" "$REGION" "$MUT" \
      > "$AGENTS/$NAME.candidate.md"
    echo "$AGENTS/$NAME.candidate.md"
    ;;
  decide)
    NAME=${2:?"usage: $0 decide <adapter-name> <bench-current.json> <bench-candidate.json>"}
    CURJSON=${3:?"usage: $0 decide <adapter-name> <bench-current.json> <bench-candidate.json>"}
    CANDJSON=${4:?"usage: $0 decide <adapter-name> <bench-current.json> <bench-candidate.json>"}
    node "$ROOT/lib/evolve/decide.mjs" "$LEDGER" "$NAME" "$CURJSON" "$CANDJSON"
    ;;
  promote)
    NAME=${2:?"usage: $0 promote <adapter-name>"}
    node "$ROOT/lib/evolve/promote.mjs" "$LEDGER" "$AGENTS" "$NAME"
    ;;
esac
