#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  TMP_HOME="$(mktemp -d)"
  cp -r "${REPO_ROOT}/tests/research-engine/fixtures/dream-input-sessions"/. "${TMP_HOME}/"
  mkdir -p "${TMP_HOME}/docs/dreams/drm_active-fixture"
  mkdir -p "${TMP_HOME}/docs/dreams/drm_discarded-fixture"
  cp "${REPO_ROOT}/tests/research-engine/fixtures/dreams/active/README.md" "${TMP_HOME}/docs/dreams/drm_active-fixture/"
  cp "${REPO_ROOT}/tests/research-engine/fixtures/dreams/discarded/README.md" "${TMP_HOME}/docs/dreams/drm_discarded-fixture/"
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  export REPO_ROOT TMP_HOME
}

teardown() {
  rm -rf "${TMP_HOME}"
  rm -f /tmp/dream-output-e2e.json
}

@test "dream e2e: memory_query는 active만 dream_insights에 포함" {
  cd "${TMP_HOME}"
  active_count=$(jq '[.dreams[] | select(.status == "active")] | length' "${TMP_HOME}/research/_index/manifest.json")
  discarded_count=$(jq '[.dreams[] | select(.status == "discarded")] | length' "${TMP_HOME}/research/_index/manifest.json")
  [ "$active_count" -ge 1 ]
  [ "$discarded_count" -ge 1 ]

  TARGET='{"input_type":"arxiv","topics":[],"intent":{"purpose":"x"}}'
  run bash "${REPO_ROOT}/scripts/memory_query.sh" --target-json "${TARGET}"
  [ "$status" -eq 0 ]
  # dream_insights 안에 discarded는 없어야 함
  ! echo "$output" | jq -r '.dream_insights[].path' | grep -q "discarded"
  # active는 있어야 함
  echo "$output" | jq -r '.dream_insights[].path' | grep -q "active"
}

@test "dream e2e: status active → discarded 편집 후 reindex → memory_query에서 제외" {
  cd "${TMP_HOME}"
  sed -i 's/status: "active"/status: "discarded"/' "${TMP_HOME}/docs/dreams/drm_active-fixture/README.md"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"

  TARGET='{"input_type":"arxiv","topics":[],"intent":{"purpose":"x"}}'
  run bash "${REPO_ROOT}/scripts/memory_query.sh" --target-json "${TARGET}"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '.dream_insights | length')" = "0" ]
}

@test "dream e2e: 풀 사이클 — mint → finalize → ledger 리셋 + manifest dreamed_in 업데이트" {
  cd "${TMP_HOME}"
  ALL_SLUGS=$(jq -r '.sessions | map(.slug) | join(",")' "${TMP_HOME}/research/_index/manifest.json")

  MINT=$(bash "${REPO_ROOT}/scripts/dream_run.sh" --mint-only --slugs "${ALL_SLUGS}")
  RUN_ID=$(echo "${MINT}" | jq -r '.run_id')

  cat > /tmp/dream-output-e2e.json <<EOF
{
  "run_id": "${RUN_ID}",
  "input_count": 3,
  "patterns": {
    "recurring_intents": [
      { "cluster_name": "agent memory", "evidence_slugs": ["2026-05-10-dream-input-a","2026-05-11-dream-input-b"], "body": "agent memory 반복 주제", "action": "topic boost" }
    ]
  },
  "failures": []
}
EOF

  bash "${REPO_ROOT}/scripts/dream_run.sh" --finalize --run-id "${RUN_ID}" --agent-output /tmp/dream-output-e2e.json

  [ -f "${TMP_HOME}/docs/dreams/${RUN_ID}/README.md" ]
  [ -f "${TMP_HOME}/docs/dreams/${RUN_ID}/insights/pattern-recurring-intents.md" ]
  grep -q 'status: "active"' "${TMP_HOME}/docs/dreams/${RUN_ID}/README.md"

  [ "$(jq -r '.last_dream_run_id' "${TMP_HOME}/research/_index/dream-ledger.json")" = "${RUN_ID}" ]
  [ "$(jq '.sessions_since_last_dream | length' "${TMP_HOME}/research/_index/dream-ledger.json")" = "0" ]

  count=$(jq --arg r "${RUN_ID}" '[.sessions[] | select(.dreamed_in | index($r))] | length' "${TMP_HOME}/research/_index/manifest.json")
  [ "$count" = "3" ]
}
