#!/usr/bin/env bash
# herdr_orchestrate.sh <slug> <run_dir>
#
# 가정: HERDR_ENV=1, herdr CLI 가 PATH 에.
# pane 4개:
#   1) claude-build : claude -p
#   2) codex-build  : codex exec --dangerously-bypass-approvals-and-sandbox
#   3) claude-critic: claude -p
#   4) codex-critic : codex exec --dangerously-bypass-approvals-and-sandbox

set -euo pipefail

SLUG="${1:?slug required}"
RUN_DIR="${2:?run_dir required}"

if [[ -z "${HERDR_ENV:-}" ]]; then
  echo "[orchestrate] HERDR_ENV not set — must run inside herdr session" >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
RESEARCH_DIR="research/${SLUG}"
HANDOFF_DIR="${RESEARCH_DIR}/design/handoff"
SCENARIOS="${RESEARCH_DIR}/design/scenarios.json"

[[ -d "${HANDOFF_DIR}" ]] || { echo "missing ${HANDOFF_DIR}" >&2; exit 1; }
[[ -f "${SCENARIOS}" ]] || { echo "missing ${SCENARIOS}" >&2; exit 1; }

# 4개 worktree 생성 + 컨텍스트 복사
for kind in claude-build codex-build claude-critic codex-critic; do
  wt="${RUN_DIR}/wt-${kind}"
  rm -rf "${wt}"
  git worktree add -d "${wt}" >/dev/null
  mkdir -p "${wt}/run"
  cp -r "${HANDOFF_DIR}" "${wt}/run/handoff"
  cp "${SCENARIOS}" "${wt}/run/scenarios.json"

  # builder pane 만 scaffold 미리 실행
  if [[ "${kind}" == *-build ]]; then
    node -e "
      import('${REPO_ROOT}/lib/design_handoff_parser.mjs').then(p =>
        import('${REPO_ROOT}/lib/app_scaffold.mjs').then(s => {
          const h = p.parseHandoff('${wt}/run/handoff');
          s.scaffoldApp({ outDir: '${wt}/run/app', handoff: h, slug: '${SLUG}', title: h.meta.title || '${SLUG}' });
        })
      );
    "
  fi
done

# pane 생성 + 명령 전송
herdr pane new --name claude-build --cwd "${RUN_DIR}/wt-claude-build/run"
herdr pane send claude-build "claude -p --append-system-prompt \"\$(cat ${REPO_ROOT}/agents/design-builder.md)\" 'build the app per agents/design-builder.md. exit when ./WORKER_DONE exists'"

herdr pane new --name codex-build --cwd "${RUN_DIR}/wt-codex-build/run"
herdr pane send codex-build "codex exec --dangerously-bypass-approvals-and-sandbox --system \"\$(cat ${REPO_ROOT}/agents/design-builder.md)\" 'build the app per agents/design-builder.md. exit when ./WORKER_DONE exists'"

# 두 build pane 종료 대기 (60분 cap)
deadline=$(( $(date +%s) + 3600 ))
while (( $(date +%s) < deadline )); do
  if [[ -f "${RUN_DIR}/wt-claude-build/run/WORKER_DONE" && -f "${RUN_DIR}/wt-codex-build/run/WORKER_DONE" ]]; then
    break
  fi
  sleep 15
done

[[ -f "${RUN_DIR}/wt-claude-build/run/WORKER_DONE" ]] || { echo "[orchestrate] claude-build did not finish" >&2; exit 2; }
[[ -f "${RUN_DIR}/wt-codex-build/run/WORKER_DONE" ]] || { echo "[orchestrate] codex-build did not finish" >&2; exit 2; }

# critic worktree 셋업
cp -r "${RUN_DIR}/wt-codex-build/run/app" "${RUN_DIR}/wt-claude-critic/run/peer-app"
cp -r "${RUN_DIR}/wt-claude-build/run/app" "${RUN_DIR}/wt-claude-critic/run/own-app"
cp -r "${RUN_DIR}/wt-claude-build/run/app" "${RUN_DIR}/wt-codex-critic/run/peer-app"
cp -r "${RUN_DIR}/wt-codex-build/run/app" "${RUN_DIR}/wt-codex-critic/run/own-app"

herdr pane new --name claude-critic --cwd "${RUN_DIR}/wt-claude-critic/run"
herdr pane send claude-critic "claude -p --append-system-prompt \"\$(cat ${REPO_ROOT}/agents/design-critic.md)\" 'review peer-app, write review-notes.md'"

herdr pane new --name codex-critic --cwd "${RUN_DIR}/wt-codex-critic/run"
herdr pane send codex-critic "codex exec --dangerously-bypass-approvals-and-sandbox --system \"\$(cat ${REPO_ROOT}/agents/design-critic.md)\" 'review peer-app, write review-notes.md'"

deadline=$(( $(date +%s) + 1800 ))
while (( $(date +%s) < deadline )); do
  if [[ -f "${RUN_DIR}/wt-claude-critic/run/review-notes.md" && -f "${RUN_DIR}/wt-codex-critic/run/review-notes.md" ]]; then
    break
  fi
  sleep 10
done

echo "[orchestrate] all 4 panes finished" >&2
