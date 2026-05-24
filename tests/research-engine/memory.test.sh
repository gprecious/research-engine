#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  FIXTURE_BASE="${REPO_ROOT}/tests/research-engine/fixtures/memory"
  TMP_HOME="$(mktemp -d)"
  cp -r "${FIXTURE_BASE}/manifest-3-sessions"/. "${TMP_HOME}/"
  export REPO_ROOT TMP_HOME
}

teardown() {
  rm -rf "${TMP_HOME}"
}

@test "memory_reindex: 빈 디렉토리 → 빈 sessions·dreams manifest" {
  EMPTY_DIR="$(mktemp -d)"
  mkdir -p "${EMPTY_DIR}/research" "${EMPTY_DIR}/docs/dreams"
  cd "${EMPTY_DIR}"
  run bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  [ "$status" -eq 0 ]
  [ -f "${EMPTY_DIR}/research/_index/manifest.json" ]
  [ "$(jq '.sessions | length' "${EMPTY_DIR}/research/_index/manifest.json")" = "0" ]
  [ "$(jq '.dreams | length' "${EMPTY_DIR}/research/_index/manifest.json")" = "0" ]
  rm -rf "${EMPTY_DIR}"
}

@test "memory_reindex: 3-sessions fixture → manifest.sessions.length == 3" {
  cd "${TMP_HOME}"
  run bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  [ "$status" -eq 0 ]
  [ "$(jq '.sessions | length' "${TMP_HOME}/research/_index/manifest.json")" = "3" ]
}

@test "memory_reindex: 두 번 연속 실행 결과 byte-identical (idempotent)" {
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  jq 'del(.generated_at) | del(.generator)' "${TMP_HOME}/research/_index/manifest.json" > /tmp/m1.json
  sleep 1
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  jq 'del(.generated_at) | del(.generator)' "${TMP_HOME}/research/_index/manifest.json" > /tmp/m2.json
  run diff /tmp/m1.json /tmp/m2.json
  [ "$status" -eq 0 ]
}

@test "memory_reindex: 기존 세션 파일 mtime 불변" {
  cd "${TMP_HOME}"
  before=$(stat -c %Y "${TMP_HOME}/research/2026-05-01-fixture-a/sources.json")
  sleep 1
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  after=$(stat -c %Y "${TMP_HOME}/research/2026-05-01-fixture-a/sources.json")
  [ "$before" = "$after" ]
}

@test "memory_reindex: ledger 동시 생성" {
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  [ -f "${TMP_HOME}/research/_index/dream-ledger.json" ]
  [ "$(jq '.version' "${TMP_HOME}/research/_index/dream-ledger.json")" = "1" ]
  [ "$(jq '.sessions_since_last_dream | length' "${TMP_HOME}/research/_index/dream-ledger.json")" = "3" ]
}

@test "memory_query: manifest 부재 시 빈 결과 + exit 0 (fail-soft)" {
  EMPTY_DIR="$(mktemp -d)"
  mkdir -p "${EMPTY_DIR}/research"
  cd "${EMPTY_DIR}"
  TARGET_JSON='{"input_type":"youtube","topics":["agent memory"],"intent":{"purpose":"메모리 패턴"}}'
  run --separate-stderr bash "${REPO_ROOT}/scripts/memory_query.sh" --target-json "${TARGET_JSON}"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '.similar_sessions | length')" = "0" ]
  [ "$(echo "$output" | jq '.dream_insights | length')" = "0" ]
  rm -rf "${EMPTY_DIR}"
}

@test "memory_query: 3-sessions fixture → youtube 유사 검색 시 1~2개 반환" {
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  TARGET_JSON='{"input_type":"youtube","topics":[],"intent":{"purpose":"에이전트 메모리 영상 정리"}}'
  run --separate-stderr bash "${REPO_ROOT}/scripts/memory_query.sh" --target-json "${TARGET_JSON}" --top-k 5
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq '.similar_sessions | length')
  [ "$count" -ge 1 ]
  [ "$count" -le 2 ]
}

@test "memory_query: --self-slug 자기 제외" {
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  TARGET_JSON='{"input_type":"youtube","topics":[],"intent":{"purpose":"에이전트 메모리 영상 정리"}}'
  run --separate-stderr bash "${REPO_ROOT}/scripts/memory_query.sh" --target-json "${TARGET_JSON}" --top-k 5 --self-slug 2026-05-03-fixture-c
  [ "$status" -eq 0 ]
  ! echo "$output" | jq -r '.similar_sessions[].slug' | grep -q "2026-05-03-fixture-c"
}
