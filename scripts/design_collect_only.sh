#!/usr/bin/env bash
# design_collect_only.sh <slug> [--from-url <handoff-api-url>] [--fresh] [--login-headful]
#   - claude.ai/design 핸드오프만 받아온다 (build/deploy 분리됨)
#   - 기존 design/handoff/index.html + meta.json 존재시 skip (cache mode)

set -euo pipefail

SLUG=""
FROM_URL=""
FRESH=0
LOGIN_HEADFUL=0
i=1
for a in "$@"; do
  case "$a" in
    --fresh) FRESH=1 ;;
    --login-headful) LOGIN_HEADFUL=1 ;;
    --from-url) FROM_URL="${!((i+1))}" ;;
    --from-url=*) FROM_URL="${a#--from-url=}" ;;
    --*) ;;
    *) [[ -z "${SLUG}" && "$a" != http* ]] && SLUG="$a" ;;
  esac
  i=$((i+1))
done

[[ -n "${SLUG}" ]] || { echo "slug required" >&2; exit 2; }
[[ -f "research/${SLUG}/README.md" ]] || { echo "missing research/${SLUG}/README.md" >&2; exit 1; }

ISO="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_DIR="research/${SLUG}/design/runs/${ISO}"
DESIGN_DIR="research/${SLUG}/design"
mkdir -p "${RUN_DIR}"
LOG="${RUN_DIR}/log.jsonl"
log() { jq -nc --arg t "$(date -u +%FT%TZ)" --arg s "$1" --arg m "$2" '{ts:$t,stage:"design",step:$s,msg:$m}' >> "${LOG}"; }

# spec/scenarios.json 의 _meta.source_intent_hash 가 현재 intent.json 과 다르면 경고 (자동 재실행 안 함)
if [[ -f "research/${SLUG}/spec/scenarios.json" && -f "research/${SLUG}/intent.json" ]]; then
  STORED=$(jq -r '._meta.source_intent_hash // ""' "research/${SLUG}/spec/scenarios.json")
  CURRENT=$(sha256sum "research/${SLUG}/intent.json" | awk '{print $1}')
  if [[ -n "${STORED}" && "${STORED}" != "${CURRENT}" ]]; then
    echo "[design] WARN: spec/scenarios.json 의 source_intent_hash 가 현재 intent.json 과 다름. /spec 재실행 권장." >&2
    log spec.stale ""
  fi
fi

log start "slug=${SLUG}"

# Cache mode — 기존 handoff 존재시 skip
if [[ "${FRESH}" == "0" && -f "${DESIGN_DIR}/handoff/index.html" && -f "${DESIGN_DIR}/handoff/meta.json" ]]; then
  log collect.cached "using existing handoff/"
  echo "[design] using existing handoff/ — skip claude.ai automation"
  log finish ok
  exit 0
fi

# 테스트 환경에서 cache 강제 — 실제 자동화 시도 차단
if [[ "${RESEARCH_ENGINE_DESIGN_CACHE_ONLY:-0}" == "1" ]]; then
  echo "[design] cache-only mode requested but no cached handoff found" >&2
  log fail "no cache in cache-only mode"
  exit 1
fi

# 실제 자동화 — 기존 design_collect.mjs 재사용
log collect.start ""
ARGS=("${SLUG}")
[[ "${FRESH}" == "1" ]] && ARGS+=("--fresh")
[[ "${LOGIN_HEADFUL}" == "1" ]] && ARGS+=("--login-headful")
[[ -n "${FROM_URL}" ]] && ARGS+=("--from-url" "${FROM_URL}")

set +e
node scripts/design_collect.mjs "${ARGS[@]}" 2>&1 | tee -a "${RUN_DIR}/collect.log"
RC=${PIPESTATUS[0]}
set -e

if [[ "${RC}" == "11" ]]; then
  log collect.manual "design_collect printed manual prompt — pipeline halted"
  echo "[design] 수동 진행 필요. 위 안내대로 claude.ai/design 사용 후" >&2
  echo "[design]   bash scripts/design_collect_only.sh ${SLUG} --from-url <URL>" >&2
  echo "[design] 재실행." >&2
  exit 11
fi

if [[ "${RC}" != "0" ]]; then
  log collect.fail "exit ${RC}"
  exit "${RC}"
fi

log finish ok
echo "[design] ${DESIGN_DIR}/handoff/ — collected"
