#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  TMP_HOME="$(mktemp -d)"
  cp -r "${REPO_ROOT}/tests/research-engine/fixtures/memory/manifest-3-sessions"/. "${TMP_HOME}/"
  mkdir -p "${TMP_HOME}/research/2026-06-01-new-target/cache"
  export REPO_ROOT TMP_HOME
}

teardown() {
  rm -rf "${TMP_HOME}"
}

@test "Stage 2 hook: memory_query 결과가 cache/memory.json에 쓰인다 + self-exclusion" {
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"

  TARGET_JSON='{"input_type":"youtube","topics":[],"intent":{"purpose":"새 메모리 영상"},"slug":"2026-06-01-new-target"}'
  bash "${REPO_ROOT}/scripts/memory_query.sh" \
    --target-json "${TARGET_JSON}" \
    --top-k 5 \
    --self-slug 2026-06-01-new-target \
    > "${TMP_HOME}/research/2026-06-01-new-target/cache/memory.json"

  [ -f "${TMP_HOME}/research/2026-06-01-new-target/cache/memory.json" ]
  [ "$(jq '.similar_sessions | length' "${TMP_HOME}/research/2026-06-01-new-target/cache/memory.json")" -ge 1 ]
  ! jq -r '.similar_sessions[].slug' "${TMP_HOME}/research/2026-06-01-new-target/cache/memory.json" | grep -q "2026-06-01-new-target"
}
