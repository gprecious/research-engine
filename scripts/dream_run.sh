#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CWD="$(pwd)"

MODE=""
SLUGS=""
SINCE=""
RUN_ID=""
AGENT_OUTPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --resolve-only) MODE="resolve"; shift ;;
    --mint-only) MODE="mint"; shift ;;
    --finalize) MODE="finalize"; shift ;;
    --slugs) SLUGS="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --agent-output) AGENT_OUTPUT="$2"; shift 2 ;;
    *) echo "dream_run: unknown arg $1" >&2; exit 2 ;;
  esac
done

MANIFEST="${CWD}/research/_index/manifest.json"
LEDGER="${CWD}/research/_index/dream-ledger.json"

[ -f "${MANIFEST}" ] || { echo "dream_run: manifest not found, run memory_reindex.sh first" >&2; exit 3; }

resolve_inputs() {
  if [ -n "${SLUGS}" ]; then
    echo "${SLUGS}" | tr ',' '\n' | jq -R . | jq -s '{resolved: .}'
  elif [ -n "${SINCE}" ]; then
    days="${SINCE%d}"
    cutoff=$(date -u -d "${days} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ)
    jq --arg cutoff "${cutoff}" '{resolved: [.sessions[] | select(.created >= $cutoff) | .slug]}' "${MANIFEST}"
  else
    [ -f "${LEDGER}" ] || { echo "dream_run: ledger not found, run memory_reindex.sh first" >&2; exit 3; }
    jq '{resolved: .sessions_since_last_dream}' "${LEDGER}"
  fi
}

case "${MODE}" in
  resolve)
    R=$(resolve_inputs)
    n=$(echo "${R}" | jq '.resolved | length')
    if [ "${n}" -lt 2 ]; then echo "dream_run: not enough sessions (${n} < 2)" >&2; exit 4; fi
    echo "${R}"
    ;;
  mint)
    R=$(resolve_inputs)
    n=$(echo "${R}" | jq '.resolved | length')
    if [ "${n}" -lt 2 ]; then echo "dream_run: not enough sessions (${n} < 2)" >&2; exit 4; fi
    TS=$(date +%Y-%m-%d-%H%M)
    first_slug=$(echo "${R}" | jq -r '.resolved[0]')
    topic_slug=$(jq -r --arg s "${first_slug}" '.sessions[] | select(.slug == $s) | .topics[0] // "mixed"' "${MANIFEST}" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | head -c 40)
    [ -z "${topic_slug}" ] && topic_slug="mixed"
    RUN_ID="drm_${TS}-${topic_slug}"
    mkdir -p "${CWD}/docs/dreams/${RUN_ID}/insights"
    META_PATH="${CWD}/docs/dreams/${RUN_ID}/meta.json"
    META_TMP="${META_PATH}.tmp.$$"
    jq -nc \
      --arg run_id "${RUN_ID}" \
      --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson resolved "$(echo "${R}" | jq '.resolved')" \
      '{run_id: $run_id, generated_at: $now, prompt_version: "v1", model: "claude-opus-4-7", input_count: ($resolved | length), inputs: $resolved}' \
      > "${META_TMP}"
    mv "${META_TMP}" "${META_PATH}"
    jq -nc --arg run_id "${RUN_ID}" --argjson resolved "$(echo "${R}" | jq '.resolved')" '{run_id: $run_id, resolved: $resolved}'
    ;;
  finalize)
    [ -n "${RUN_ID}" ] || { echo "dream_run --finalize: --run-id required" >&2; exit 2; }
    [ -f "${AGENT_OUTPUT}" ] || { echo "dream_run --finalize: --agent-output file missing" >&2; exit 2; }
    DREAM_DIR="${CWD}/docs/dreams/${RUN_ID}"
    [ -d "${DREAM_DIR}" ] || { echo "dream_run: ${DREAM_DIR} not found (run --mint-only first)" >&2; exit 5; }

    AGENT_JSON="$(cat "${AGENT_OUTPUT}")"
    for category in adapter_failure_modes recurring_intents prior_art_clusters topic_coverage_gaps; do
      items=$(echo "${AGENT_JSON}" | jq --arg c "${category}" '.patterns[$c] // []')
      n=$(echo "${items}" | jq 'length')
      if [ "${n}" -gt 0 ]; then
        slug=$(echo "${category}" | tr '_' '-')
        file="${DREAM_DIR}/insights/pattern-${slug}.md"
        tmp_file="${file}.tmp.$$"
        echo "# ${category//_/ }" > "${tmp_file}"
        echo "" >> "${tmp_file}"
        echo "${items}" | jq -r '.[] | "## " + (.cluster_name // .title // .name // .topic // "") + "\n\n" + (.body // "") + "\n\n**Evidence:** " + ((.evidence_slugs // []) | join(", ")) + "\n\n**Action:** " + (.action // "") + "\n"' >> "${tmp_file}"
        mv "${tmp_file}" "${file}"
      fi
    done

    INPUTS_INLINE=$(jq -r '.inputs | map("\"" + . + "\"") | join(", ")' "${DREAM_DIR}/meta.json")
    INPUT_COUNT=$(jq -r '.input_count' "${DREAM_DIR}/meta.json")
    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    README_TMP="${DREAM_DIR}/README.md.tmp.$$"
    cat > "${README_TMP}" <<EOF
---
run_id: "${RUN_ID}"
created: "${NOW}"
inputs: [${INPUTS_INLINE}]
status: "active"
supersedes: null
---

# Dream ${RUN_ID}

Cross-session patterns extracted from ${INPUT_COUNT} input sessions.

EOF
    for f in "${DREAM_DIR}/insights"/*.md; do
      [ -f "$f" ] || continue
      title=$(head -1 "$f" | sed 's/^# //')
      echo "- See \`insights/$(basename "$f")\` — ${title}" >> "${README_TMP}"
    done
    mv "${README_TMP}" "${DREAM_DIR}/README.md"

    inputs_with_hash="[]"
    while IFS= read -r slug; do
      hash=$(jq -r --arg s "${slug}" '.sessions[] | select(.slug == $s) | .content_sha256 // ""' "${MANIFEST}")
      inputs_with_hash=$(echo "${inputs_with_hash}" | jq --arg s "${slug}" --arg h "${hash}" '. + [{slug: $s, content_sha256: $h}]')
    done < <(jq -r '.inputs[]' "${DREAM_DIR}/meta.json")
    SOURCES_TMP="${DREAM_DIR}/sources.json.tmp.$$"
    jq -nc --argjson i "${inputs_with_hash}" '{inputs: ($i | map(.slug)), input_hashes: $i}' > "${SOURCES_TMP}"
    mv "${SOURCES_TMP}" "${DREAM_DIR}/sources.json"

    node "${REPO_ROOT}/lib/memory/ledger.mjs" --reset --run-id "${RUN_ID}" --ledger "${LEDGER}"
    bash "${SCRIPT_DIR}/memory_reindex.sh"

    echo "{\"run_id\":\"${RUN_ID}\",\"path\":\"docs/dreams/${RUN_ID}\"}"
    ;;
  *)
    echo "dream_run: must specify --resolve-only|--mint-only|--finalize" >&2
    exit 2
    ;;
esac
