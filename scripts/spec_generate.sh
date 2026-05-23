#!/usr/bin/env bash
# spec_generate.sh <slug>
#   - LLM 으로 scenarios.json + spec.md 생성
#   - ajv strict validate (G0 게이트)
#   - research/<slug>/spec/{scenarios.json, spec.md, runs/<ISO>/log.jsonl} 작성

set -euo pipefail

SLUG="${1:-}"
[[ -n "${SLUG}" ]] || { echo "slug required" >&2; exit 2; }
[[ -f "research/${SLUG}/README.md" ]] || { echo "missing research/${SLUG}/README.md" >&2; exit 1; }

INTENT="research/${SLUG}/intent.json"
[[ -f "${INTENT}" ]] || INTENT=""

ISO="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_DIR="research/${SLUG}/spec/runs/${ISO}"
SPEC_DIR="research/${SLUG}/spec"
mkdir -p "${RUN_DIR}" "${SPEC_DIR}"
LOG="${RUN_DIR}/log.jsonl"
log() { jq -nc --arg t "$(date -u +%FT%TZ)" --arg s "$1" --arg m "$2" '{ts:$t,stage:"spec",step:$s,msg:$m}' >> "${LOG}"; }

log start "slug=${SLUG}"

INTENT_HASH=""
INTENT_CONTENT="{}"
if [[ -n "${INTENT}" ]]; then
  INTENT_HASH=$(sha256sum "${INTENT}" | awk '{print $1}')
  INTENT_CONTENT=$(cat "${INTENT}")
fi

README_CONTENT=$(cat "research/${SLUG}/README.md")

PROMPT_INPUT=$(jq -nc \
  --arg slug "${SLUG}" \
  --arg readme "${README_CONTENT}" \
  --argjson intent "${INTENT_CONTENT}" \
  --arg intent_hash "${INTENT_HASH}" \
  --arg schema_path "tests/research-engine/schemas/scenarios.schema.json" \
  '{slug:$slug, readme:$readme, intent:$intent, intent_hash:$intent_hash, schema_path:$schema_path}')

# LLM 호출 — claude CLI 사용. spec-author persona 를 system prompt 로. input 은 prompt 본문에 첨부.
log llm.call ""
SYSTEM_PROMPT=$(cat agents/spec-author.md)
USER_PROMPT=$(printf 'spec-author: produce scenarios + spec.md from the JSON below.\n\n```json\n%s\n```' "${PROMPT_INPUT}")
LLM_OUT=$(claude -p --append-system-prompt "${SYSTEM_PROMPT}" "${USER_PROMPT}" 2>>"${RUN_DIR}/llm.stderr" || true)

# fenced JSON 블록만 추출
JSON_BLOCK=$(echo "${LLM_OUT}" | awk '/^```/{f=!f;next} f' | head -c 500000)
[[ -n "${JSON_BLOCK}" ]] || JSON_BLOCK="${LLM_OUT}"

# scenarios + spec_md 분리
SCENARIOS=$(echo "${JSON_BLOCK}" | jq '.scenarios')
SPEC_MD=$(echo "${JSON_BLOCK}" | jq -r '.spec_md')

if [[ "${SCENARIOS}" == "null" || -z "${SCENARIOS}" ]]; then
  log llm.fail "no scenarios in output"
  echo "[spec] LLM did not produce valid output. See ${RUN_DIR}/llm.stderr" >&2
  exit 1
fi

# _meta 보강 (LLM 이 누락했을 수 있음)
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
SCENARIOS=$(echo "${SCENARIOS}" | jq \
  --arg by "spec-author@${GIT_SHA}" \
  --arg at "$(date -u +%FT%TZ)" \
  --arg ih "${INTENT_HASH:-0000000000000000000000000000000000000000000000000000000000000000}" \
  '._meta = {generated_by:$by, generated_at:$at, source_intent_hash:$ih}')

echo "${SCENARIOS}" > "${SPEC_DIR}/scenarios.json"
printf '%s\n' "${SPEC_MD}" > "${SPEC_DIR}/spec.md"

# G0 게이트 — ajv strict validate
log g0.start ""
if node --input-type=module -e "
import { validateScenariosFile } from './lib/scenarios_validator.mjs';
const r = validateScenariosFile('${SPEC_DIR}/scenarios.json');
if (!r.valid) {
  console.error(JSON.stringify(r.errors, null, 2));
  process.exit(1);
}
"; then
  log g0.ok ""
else
  log g0.fail "scenarios.json failed schema validation"
  echo "[spec] G0 gate failed — see above" >&2
  exit 1
fi

log finish ok
echo "[spec] ${SPEC_DIR}/scenarios.json + spec.md — G0 PASS"
