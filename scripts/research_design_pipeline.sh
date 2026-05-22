#!/usr/bin/env bash
# research_design_pipeline.sh <slug> [--no-deploy] [--login-headful] [--fresh]

set -euo pipefail

SLUG=""
NO_DEPLOY=0
LOGIN_HEADFUL=0
FRESH=0

for a in "$@"; do
  case "$a" in
    --no-deploy) NO_DEPLOY=1 ;;
    --login-headful) LOGIN_HEADFUL=1 ;;
    --fresh) FRESH=1 ;;
    --*) echo "unknown flag $a" >&2; exit 2 ;;
    *) SLUG="$a" ;;
  esac
done

[[ -n "${SLUG}" ]] || { echo "slug required" >&2; exit 2; }
[[ -f "research/${SLUG}/README.md" ]] || { echo "missing research/${SLUG}/README.md" >&2; exit 1; }

ISO="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_DIR="research/${SLUG}/design/runs/${ISO}"
mkdir -p "${RUN_DIR}"
LOG="${RUN_DIR}/log.jsonl"
log() { jq -nc --arg t "$(date -u +%FT%TZ)" --arg s "$1" --arg m "$2" '{ts:$t,step:$s,msg:$m}' >> "${LOG}"; }

# mock 모드 — pipeline.test.sh 가 사용. scenarios.json 체크는 mock 분기에서는 건너뛴다.
if [[ "${RESEARCH_DESIGN_MOCK:-}" == "1" ]]; then
  log start mock-mode
  log finish mock-mode
  echo "[mock] pipeline run finished — log at ${LOG}" >&2
  exit 0
fi

[[ -f "research/${SLUG}/design/scenarios.json" ]] || { echo "missing research/${SLUG}/design/scenarios.json" >&2; exit 1; }

log start "slug=${SLUG}"

if [[ "${FRESH}" == "1" ]]; then
  rm -f "${HOME}/.config/research-engine/claude-design/storageState.json" || true
fi

if [[ "${LOGIN_HEADFUL}" == "1" ]]; then
  log login.manual ""
  node scripts/manual_login.mjs || { log fatal "manual_login failed"; exit 1; }
fi

log collect.start ""
node scripts/design_collect.mjs "${SLUG}" 2>&1 | tee -a "${RUN_DIR}/collect.log"
log collect.done ""

log orchestrate.start ""
bash scripts/herdr_orchestrate.sh "${SLUG}" "${RUN_DIR}"
log orchestrate.done ""

for kind in claude-build codex-build; do
  WT="${RUN_DIR}/wt-${kind}/run"
  if [[ ! -f "${WT}/WORKER_DONE" ]]; then
    log g1.fail "${kind} no WORKER_DONE"
    exit 2
  fi
  J="${WT}/app/judge.json"
  [[ -f "${J}" ]] || { log g1.fail "${kind} no judge.json"; exit 2; }
  TOTAL=$(jq '.total' "${J}")
  log g1.ok "${kind} total=${TOTAL}"
done

MERGE_WT="${RUN_DIR}/wt-merge"
git worktree add -d "${MERGE_WT}" >/dev/null
mkdir -p "${MERGE_WT}/run"
cp -r "${RUN_DIR}/wt-claude-build/run/app" "${MERGE_WT}/run/claude-app"
cp -r "${RUN_DIR}/wt-codex-build/run/app" "${MERGE_WT}/run/codex-app"
cp "${RUN_DIR}/wt-claude-critic/run/review-notes.md" "${MERGE_WT}/run/claude-review.md"
cp "${RUN_DIR}/wt-codex-critic/run/review-notes.md" "${MERGE_WT}/run/codex-review.md"
cp -r "research/${SLUG}/design/handoff" "${MERGE_WT}/run/handoff"
cp "research/${SLUG}/design/scenarios.json" "${MERGE_WT}/run/scenarios.json"

herdr pane new --name merger --cwd "${MERGE_WT}/run"
herdr pane send merger "claude -p --append-system-prompt \"\$(cat $(pwd)/agents/design-merger.md)\" 'merge per agents/design-merger.md until G2 GREEN'"

deadline=$(( $(date +%s) + 1800 ))
while (( $(date +%s) < deadline )); do
  [[ -d "${MERGE_WT}/run/merged-app" ]] && break
  sleep 10
done
[[ -d "${MERGE_WT}/run/merged-app" ]] || { log g2.fail "merger no merged-app"; exit 3; }

pushd "${MERGE_WT}/run/merged-app" >/dev/null
pnpm install --frozen-lockfile
pnpm build
E2E_BASE_URL=http://localhost:3000 pnpm start &
APP_PID=$!
sleep 5
E2E_PASS=0
if E2E_BASE_URL=http://localhost:3000 pnpm --prefix "$(git rev-parse --show-toplevel)" test:e2e; then E2E_PASS=1; fi
kill "${APP_PID}" || true
popd >/dev/null
[[ "${E2E_PASS}" == "1" ]] || { log g2.fail "merged e2e failed"; exit 3; }
log g2.ok ""

rm -rf "research/${SLUG}/design/app"
cp -r "${MERGE_WT}/run/merged-app" "research/${SLUG}/design/app"
log stamp.done ""

if [[ "${NO_DEPLOY}" == "1" ]]; then
  log deploy.skipped ""
else
  HOST=$(bash scripts/lxc_deploy.sh "${SLUG}" "research/${SLUG}/design/app")
  echo "${HOST}" > "${RUN_DIR}/host.txt"
  log deploy.done "host=${HOST}"

  if [[ -n "${HOST}" ]]; then
    sleep 10
    if E2E_BASE_URL="https://${HOST}" pnpm test:e2e; then
      log g3.ok "host=${HOST}"
    else
      log g3.fail "host=${HOST}"
      exit 4
    fi
  fi
fi

{
  echo "# ${SLUG} design"
  echo
  echo "- run: ${ISO}"
  [[ -f "${RUN_DIR}/host.txt" ]] && echo "- host: $(cat ${RUN_DIR}/host.txt)"
  echo "- gates: $(jq -s 'map(select(.step | startswith("g"))) | map(.step + "=" + .msg) | join(", ")' "${LOG}")"
} > "research/${SLUG}/design/README.md"

log finish ok
echo "[pipeline] done — ${RUN_DIR}"
