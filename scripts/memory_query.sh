#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CWD="$(pwd)"

MANIFEST="${CWD}/research/_index/manifest.json"
TOP_K=5
TARGET_JSON=""
SELF_SLUG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --target-json) TARGET_JSON="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --top-k) TOP_K="${2:-5}"; shift; [ $# -gt 0 ] && shift ;;
    --self-slug) SELF_SLUG="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    *) shift ;;
  esac
done

empty='{"similar_sessions":[],"dream_insights":[]}'

if [ ! -f "${MANIFEST}" ]; then
  echo "memory_query: manifest missing, run memory_reindex.sh to generate" >&2
  echo "${empty}"
  exit 0
fi

if [ -z "${TARGET_JSON}" ]; then
  echo "memory_query: --target-json required" >&2
  echo "${empty}"
  exit 0
fi

# delegate to Node CLI
if [ -n "${SELF_SLUG}" ]; then
  node "${REPO_ROOT}/lib/memory/query_cli.mjs" \
    --manifest "${MANIFEST}" \
    --target-json "${TARGET_JSON}" \
    --top-k "${TOP_K}" \
    --self-slug "${SELF_SLUG}"
else
  node "${REPO_ROOT}/lib/memory/query_cli.mjs" \
    --manifest "${MANIFEST}" \
    --target-json "${TARGET_JSON}" \
    --top-k "${TOP_K}"
fi
