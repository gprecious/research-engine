#!/usr/bin/env bash
# deploy_dispatch.sh <slug> [--target lxc]
#   - app/ 검증 → deploy-planner agent 로 lxc_config.json 생성 → deploy_lxc.sh 호출 → G3 e2e

set -euo pipefail

SLUG=""
TARGET="lxc"
i=1
for a in "$@"; do
  case "$a" in
    --target) n=$((i+1)); TARGET="${!n}" ;;
    --target=*) TARGET="${a#--target=}" ;;
    --*) ;;
    *) [[ -z "${SLUG}" ]] && SLUG="$a" ;;
  esac
  i=$((i+1))
done

[[ -n "${SLUG}" ]] || { echo "slug required" >&2; exit 2; }
[[ -d "research/${SLUG}/app" ]] || { echo "missing research/${SLUG}/app/ — 사용자 build 필요" >&2; exit 1; }
[[ -f "research/${SLUG}/app/package.json" ]] || { echo "missing research/${SLUG}/app/package.json" >&2; exit 1; }
[[ -f "research/${SLUG}/spec/scenarios.json" ]] || { echo "missing research/${SLUG}/spec/scenarios.json — /spec 실행 필요" >&2; exit 1; }

ISO="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_DIR="research/${SLUG}/deploy/runs/${ISO}"
DEPLOY_DIR="research/${SLUG}/deploy"
mkdir -p "${RUN_DIR}" "${DEPLOY_DIR}"
LOG="${RUN_DIR}/log.jsonl"
log() { jq -nc --arg t "$(date -u +%FT%TZ)" --arg s "$1" --arg m "$2" '{ts:$t,stage:"deploy",step:$s,msg:$m}' >> "${LOG}"; }

# spec staleness 경고
if [[ -f "research/${SLUG}/intent.json" ]]; then
  STORED=$(jq -r '._meta.source_intent_hash // ""' "research/${SLUG}/spec/scenarios.json")
  CURRENT=$(sha256sum "research/${SLUG}/intent.json" | awk '{print $1}')
  if [[ -n "${STORED}" && "${STORED}" != "${CURRENT}" ]]; then
    echo "[deploy] WARN: spec stale — /spec 재실행 권장" >&2
    log spec.stale ""
  fi
fi

log start "slug=${SLUG} target=${TARGET}"

# deploy-planner agent 로 lxc_config.json 생성
log planner.start ""
HINTS="{}"
[[ -f "research/${SLUG}/app/.deploy-hints.json" ]] && HINTS=$(cat "research/${SLUG}/app/.deploy-hints.json")
PKG=$(cat "research/${SLUG}/app/package.json")
HMC=""  # hetzner_master_conventions — 향후 git clone 캐시에서 읽음. 이번 작업에선 빈 문자열.

PLANNER_INPUT=$(jq -nc \
  --arg slug "${SLUG}" \
  --argjson pkg "${PKG}" \
  --argjson hints "${HINTS}" \
  --arg hmc "${HMC}" \
  '{slug:$slug, package_json:$pkg, deploy_hints:$hints, hetzner_master_conventions:$hmc}')

if [[ "${RESEARCH_ENGINE_DEPLOY_MOCK:-0}" == "1" ]]; then
  # Mock mode — LLM 호출 skip, deterministic config
  LXC_CONFIG=$(jq -nc --arg slug "${SLUG}" '{
    container_name: ("rd-" + ($slug | gsub("[^a-z0-9]"; "-")) | .[0:63]),
    image: "local:vztmpl/debian-12-standard_*.tar.zst",
    cores: 1, memory_mb: 1024, disk_gb: 10,
    runtime: "node@22", package_manager: "pnpm",
    build_cmd: "pnpm build", start_cmd: "pnpm start",
    port: 3000, static_only: false, env_keys: [],
    systemd_unit_name: "research-engine-app.service"
  }')
else
  SYSTEM_PROMPT=$(cat agents/deploy-planner.md)
  USER_PROMPT=$(printf 'deploy-planner: emit lxc_config.json from the JSON below.\n\n```json\n%s\n```' "${PLANNER_INPUT}")
  PLANNER_OUT=$(claude -p --append-system-prompt "${SYSTEM_PROMPT}" "${USER_PROMPT}" 2>>"${RUN_DIR}/planner.stderr" || true)
  LXC_CONFIG=$(echo "${PLANNER_OUT}" | awk '/^```/{f=!f;next} f' | head -c 100000)
  [[ -n "${LXC_CONFIG}" ]] || LXC_CONFIG="${PLANNER_OUT}"
fi

echo "${LXC_CONFIG}" > "${RUN_DIR}/lxc_config.json"
log planner.done ""

if [[ "${TARGET}" != "lxc" ]]; then
  log fail "unsupported target=${TARGET}"
  echo "[deploy] only --target=lxc supported in this scope" >&2
  exit 1
fi

# 이전 host 보존 (rollback 용)
PREV_HOST=""
[[ -f "${DEPLOY_DIR}/deploy.json" ]] && PREV_HOST=$(jq -r '.host // ""' "${DEPLOY_DIR}/deploy.json")

# LXC 배포
log lxc.start ""
if [[ "${RESEARCH_ENGINE_DEPLOY_MOCK:-0}" == "1" ]]; then
  HOST="mock-${SLUG}.ts.net"
  LXC_ID=999
  log lxc.mock "host=${HOST}"
else
  set +e
  HOST=$(bash scripts/deploy_lxc.sh "${SLUG}" "research/${SLUG}/app" "${RUN_DIR}/lxc_config.json" 2>>"${RUN_DIR}/adapter.log")
  RC=$?
  set -e
  if [[ "${RC}" != "0" ]]; then
    log lxc.fail "exit ${RC}"
    echo "[deploy] LXC 배포 실패 — see ${RUN_DIR}/adapter.log" >&2
    exit 4
  fi
  LXC_ID=$(grep -oP 'CTID=\K[0-9]+' "${RUN_DIR}/adapter.log" | tail -1 || echo "0")
fi
log lxc.done "host=${HOST}"

# G3 게이트 — prod URL 대상 e2e
log g3.start "baseUrl=https://${HOST}"
G3_PASSED=0
if [[ "${RESEARCH_ENGINE_DEPLOY_MOCK:-0}" == "1" ]]; then
  G3_PASSED=1
  jq -n --arg host "${HOST}" '{mock:true, host:$host, passed:true}' > "${RUN_DIR}/gate-3.json"
else
  set +e
  E2E_BASE_URL="https://${HOST}" \
  E2E_SCENARIOS_PATH="research/${SLUG}/spec/scenarios.json" \
    pnpm test:e2e:re --reporter=json > "${RUN_DIR}/gate-3.json" 2>>"${RUN_DIR}/g3.stderr"
  RC=$?
  set -e
  [[ "${RC}" == "0" ]] && G3_PASSED=1
fi

if [[ "${G3_PASSED}" == "0" ]]; then
  log g3.fail ""
  # NOTE: LXC 는 slug-idempotent — 새 배포가 기존 컨테이너를 in-place 갱신. 자동 롤백은 v1 scope 밖.
  # prev_host 는 deploy.json 에 보존되어 사용자 수동 revert 가능. 향후 별도 task.
  echo "[deploy] G3 e2e 실패 — see ${RUN_DIR}/gate-3.json" >&2
  echo "[deploy] (자동 롤백 없음 — 필요시 prev_host=${PREV_HOST} 로 수동 revert)" >&2
  exit 4
fi
log g3.ok ""

# deploy.json 작성
jq -n \
  --arg target "${TARGET}" \
  --arg host "${HOST}" \
  --argjson lxc_id "${LXC_ID}" \
  --arg deployed_at "$(date -u +%FT%TZ)" \
  --arg prev_host "${PREV_HOST}" \
  --arg report "runs/${ISO}/gate-3.json" \
  '{target:$target, host:$host, lxc_id:$lxc_id, deployed_at:$deployed_at, prev_host:$prev_host, g3:{passed:true, report:$report}}' \
  > "${DEPLOY_DIR}/deploy.json"

log finish ok
echo "[deploy] host=${HOST} — G3 PASS"
echo "${HOST}"
