#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CWD="$(pwd)"

INDEX_DIR="${CWD}/research/_index"
RESEARCH_DIR="${CWD}/research"
DREAMS_DIR="${CWD}/docs/dreams"

mkdir -p "${INDEX_DIR}"

TMP_MANIFEST="${INDEX_DIR}/manifest.json.tmp.$$"
node "${REPO_ROOT}/lib/memory/manifest_schema.mjs" --build \
  --research-dir "${RESEARCH_DIR}" \
  --dreams-dir "${DREAMS_DIR}" \
  > "${TMP_MANIFEST}"
mv "${TMP_MANIFEST}" "${INDEX_DIR}/manifest.json"

node "${REPO_ROOT}/lib/memory/ledger.mjs" --rebuild \
  --manifest "${INDEX_DIR}/manifest.json" \
  --ledger "${INDEX_DIR}/dream-ledger.json"

n_sessions=$(jq '.sessions | length' "${INDEX_DIR}/manifest.json")
n_dreams=$(jq '.dreams | length' "${INDEX_DIR}/manifest.json")
echo "memory_reindex: ${n_sessions} sessions, ${n_dreams} dreams"
