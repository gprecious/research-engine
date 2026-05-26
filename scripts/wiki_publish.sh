#!/usr/bin/env bash
set -euo pipefail
# wiki/ 콘텐츠를 Quartz 정적 사이트로 빌드(+smoke). --deploy면 rsync 배포.
VAULT="${VAULT:-$(pwd)/wiki}"
QUARTZ_DIR="${QUARTZ_DIR:-$(pwd)/wiki-site}"   # vault 밖 (nested git/ignore 충돌 방지)
DEPLOY="${1:-}"

if [ ! -d "${QUARTZ_DIR}" ]; then
  echo "Quartz 미설치. 1회 설치:" >&2
  echo "  git clone https://github.com/jackyzha0/quartz \"${QUARTZ_DIR}\" && (cd \"${QUARTZ_DIR}\" && npm i)" >&2
  exit 1
fi

CONTENT="${QUARTZ_DIR}/content"
rm -rf "${CONTENT}"; mkdir -p "${CONTENT}"
cp -r "${VAULT}/concepts" "${VAULT}/entities" "${CONTENT}/" 2>/dev/null || true
cp "${VAULT}/index.md" "${CONTENT}/index.md" 2>/dev/null || true
# 콘텐츠 복사 검증: index.md 가 실제로 들어가야 빈/기본 사이트 발행을 막는다
test -f "${CONTENT}/index.md" || { echo "publish 실패: ${VAULT}/index.md 복사 안 됨 (vault에 index.md 없음?)" >&2; exit 1; }

( cd "${QUARTZ_DIR}" && npx quartz build )
# smoke: index.html 생성 + 비어있지 않음 확인
test -f "${QUARTZ_DIR}/public/index.html" || { echo "publish smoke 실패: public/index.html 없음" >&2; exit 1; }
test -s "${QUARTZ_DIR}/public/index.html" || { echo "publish smoke 실패: public/index.html 비어있음" >&2; exit 1; }
echo "built+smoke ok: ${QUARTZ_DIR}/public"

if [ "${DEPLOY}" = "--deploy" ]; then
  # 배포는 명시적 rsync 만 (임의 명령 eval 금지 — 셸 인젝션 회피)
  : "${WIKI_DEPLOY_TARGET:?WIKI_DEPLOY_TARGET 미설정 — 예: user@host:/var/www/wiki}"
  rsync -a --delete "${QUARTZ_DIR}/public/" "${WIKI_DEPLOY_TARGET}/"
  echo "deployed → ${WIKI_DEPLOY_TARGET}"
fi
