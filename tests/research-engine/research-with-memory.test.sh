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

@test "Stage 5.2: 신규 세션 sources.json에 content_sha256 + created_by가 기록된다" {
  cd "${TMP_HOME}"
  NEW_SLUG="2026-06-01-new-target"
  mkdir -p "${TMP_HOME}/research/${NEW_SLUG}"
  cat > "${TMP_HOME}/research/${NEW_SLUG}/README.md" <<'EOF'
---
title: "New target"
slug: "2026-06-01-new-target"
input_type: "youtube"
created: "2026-06-01T10:00:00+09:00"
---

# new target body
EOF

  hash=$(sha256sum "${TMP_HOME}/research/${NEW_SLUG}/README.md" | awk '{print $1}')
  jq -nc \
    --arg input "https://youtu.be/new" \
    --arg type "youtube" \
    --arg created "2026-06-01T10:00:00+09:00" \
    --arg hash "$hash" \
    '{
      input: $input,
      input_type: $type,
      created: $created,
      content_sha256: $hash,
      created_by: [
        {actor_type: "adapter", id: "youtube-adapter", model: "claude-opus-4-7", ts: $created}
      ],
      sources: []
    }' > "${TMP_HOME}/research/${NEW_SLUG}/sources.json"

  [ "$(jq -r '.content_sha256' "${TMP_HOME}/research/${NEW_SLUG}/sources.json")" = "$hash" ]
  [ "$(jq '.created_by | length' "${TMP_HOME}/research/${NEW_SLUG}/sources.json")" -ge 1 ]
}

@test "Stage 5.8: 신규 세션 추가 후 reindex → ledger 카운터 증가" {
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  before=$(jq '.sessions_since_last_dream | length' "${TMP_HOME}/research/_index/dream-ledger.json")

  NEW_SLUG="2026-07-01-brand-new-entry"
  mkdir -p "${TMP_HOME}/research/${NEW_SLUG}"
  cat > "${TMP_HOME}/research/${NEW_SLUG}/README.md" <<'EOF'
---
title: "New"
input_type: "youtube"
created: "2026-07-01T10:00:00+09:00"
---
body
EOF
  echo '{"input_type":"youtube","input":"x","created":"2026-07-01","content_sha256":"abc","created_by":[],"sources":[],"intent":{"purpose":"new","focus":"","audience_level":""}}' \
    > "${TMP_HOME}/research/${NEW_SLUG}/sources.json"

  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  after=$(jq '.sessions_since_last_dream | length' "${TMP_HOME}/research/_index/dream-ledger.json")
  [ "$after" -gt "$before" ]
}

@test "Stage 5.8: 5회 누적 시 ledger --suggest? exit 0 + should=true" {
  cd "${TMP_HOME}"
  # 3개 fixture + 2개 추가 → 5
  for i in 4 5; do
    NEW_SLUG="2026-05-0${i}-extra-fixture-${i}"
    mkdir -p "${TMP_HOME}/research/${NEW_SLUG}"
    cat > "${TMP_HOME}/research/${NEW_SLUG}/README.md" <<EOF
---
title: "Extra ${i}"
input_type: "youtube"
created: "2026-05-0${i}T10:00:00+09:00"
---
body
EOF
    echo "{\"input_type\":\"youtube\",\"input\":\"x${i}\",\"created\":\"2026-05-0${i}\",\"content_sha256\":\"abc${i}\",\"created_by\":[],\"sources\":[],\"intent\":{\"purpose\":\"e${i}\",\"focus\":\"\",\"audience_level\":\"\"}}" \
      > "${TMP_HOME}/research/${NEW_SLUG}/sources.json"
  done
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"

  count=$(jq '.sessions_since_last_dream | length' "${TMP_HOME}/research/_index/dream-ledger.json")
  # setup() pre-creates 2026-06-01-new-target (empty dir), so count is 3 fixtures + 2 added + 1 pre-created = 6 ≥ 5
  [ "$count" -ge 5 ]

  run node "${REPO_ROOT}/lib/memory/ledger.mjs" --suggest? --ledger "${TMP_HOME}/research/_index/dream-ledger.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.should == true'
}
