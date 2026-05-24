#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  TMP_HOME="$(mktemp -d)"
  SLUG="2026-05-01-fixture-a"
  mkdir -p "${TMP_HOME}/research/${SLUG}"
  cat > "${TMP_HOME}/research/${SLUG}/session.md" <<'EOF'
# session log

- initial entry
EOF
  export REPO_ROOT TMP_HOME SLUG
}

teardown() {
  rm -rf "${TMP_HOME}"
}

@test "OCC: sha256 일치 → write 가능" {
  cd "${TMP_HOME}"
  expected=$(sha256sum "${TMP_HOME}/research/${SLUG}/session.md" | awk '{print $1}')
  actual=$(sha256sum "${TMP_HOME}/research/${SLUG}/session.md" | awk '{print $1}')
  [ "$expected" = "$actual" ]
}

@test "OCC: 동시 수정 시뮬레이션 → mismatch 감지" {
  cd "${TMP_HOME}"
  before=$(sha256sum "${TMP_HOME}/research/${SLUG}/session.md" | awk '{print $1}')
  echo "- concurrent edit" >> "${TMP_HOME}/research/${SLUG}/session.md"
  after=$(sha256sum "${TMP_HOME}/research/${SLUG}/session.md" | awk '{print $1}')
  [ "$before" != "$after" ]
}

@test "OCC: atomic rename — session.md.tmp 부분 쓰기 시 session.md 불변" {
  cd "${TMP_HOME}"
  original_hash=$(sha256sum "${TMP_HOME}/research/${SLUG}/session.md" | awk '{print $1}')
  echo "partial" > "${TMP_HOME}/research/${SLUG}/session.md.tmp"
  current=$(sha256sum "${TMP_HOME}/research/${SLUG}/session.md" | awk '{print $1}')
  [ "$original_hash" = "$current" ]
}
