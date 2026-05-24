#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  TMP_HOME="$(mktemp -d)"
  cp -r "${REPO_ROOT}/tests/research-engine/fixtures/dream-input-sessions"/. "${TMP_HOME}/"
  export REPO_ROOT TMP_HOME
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
}

teardown() {
  rm -rf "${TMP_HOME}"
}

@test "dream_run: 입력 세션 < 2 → not enough sessions 에러" {
  SINGLE=$(jq -r '.sessions[0].slug' "${TMP_HOME}/research/_index/manifest.json")
  run --separate-stderr bash "${REPO_ROOT}/scripts/dream_run.sh" --resolve-only --slugs "${SINGLE}"
  [ "$status" -ne 0 ]
  echo "$stderr" | grep -q "not enough sessions"
}

@test "dream_run: --slugs=a,b,c → 정확히 3개 resolved" {
  ALL_SLUGS=$(jq -r '.sessions | map(.slug) | join(",")' "${TMP_HOME}/research/_index/manifest.json")
  run bash "${REPO_ROOT}/scripts/dream_run.sh" --resolve-only --slugs "${ALL_SLUGS}"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.resolved | length == 3'
}

@test "dream_run: --mint-only → 디렉토리 + meta.json 생성" {
  ALL_SLUGS=$(jq -r '.sessions | map(.slug) | join(",")' "${TMP_HOME}/research/_index/manifest.json")
  run bash "${REPO_ROOT}/scripts/dream_run.sh" --mint-only --slugs "${ALL_SLUGS}"
  [ "$status" -eq 0 ]
  RUN_ID=$(echo "$output" | jq -r '.run_id')
  [ -d "${TMP_HOME}/docs/dreams/${RUN_ID}" ]
  [ -d "${TMP_HOME}/docs/dreams/${RUN_ID}/insights" ]
  [ -f "${TMP_HOME}/docs/dreams/${RUN_ID}/meta.json" ]
}

@test "dream_run: --finalize → insights/ + README.md + sources.json + ledger 리셋" {
  ALL_SLUGS=$(jq -r '.sessions | map(.slug) | join(",")' "${TMP_HOME}/research/_index/manifest.json")
  MINT=$(bash "${REPO_ROOT}/scripts/dream_run.sh" --mint-only --slugs "${ALL_SLUGS}")
  RUN_ID=$(echo "${MINT}" | jq -r '.run_id')

  cat > /tmp/dream-output.json <<EOF
{
  "run_id": "${RUN_ID}",
  "input_count": 3,
  "patterns": {
    "recurring_intents": [
      { "cluster_name": "agent memory", "evidence_slugs": ["2026-05-10-dream-input-a","2026-05-11-dream-input-b"], "body": "사용자가 agent memory 주제를 반복 검색함", "action": "research-engine memory query에 agent memory 토픽 boost 권장" }
    ]
  },
  "failures": []
}
EOF

  run bash "${REPO_ROOT}/scripts/dream_run.sh" --finalize --run-id "${RUN_ID}" --agent-output /tmp/dream-output.json
  [ "$status" -eq 0 ]
  [ -f "${TMP_HOME}/docs/dreams/${RUN_ID}/README.md" ]
  [ -f "${TMP_HOME}/docs/dreams/${RUN_ID}/sources.json" ]
  [ -f "${TMP_HOME}/docs/dreams/${RUN_ID}/insights/pattern-recurring-intents.md" ]
  [ "$(jq -r '.last_dream_run_id' "${TMP_HOME}/research/_index/dream-ledger.json")" = "${RUN_ID}" ]
  [ "$(jq '.sessions_since_last_dream | length' "${TMP_HOME}/research/_index/dream-ledger.json")" = "0" ]
}
