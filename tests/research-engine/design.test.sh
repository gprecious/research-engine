#!/usr/bin/env bats

SLUG="2026-05-23-design-test-fixture"
TARGET="research/${SLUG}"

setup() {
  mkdir -p "${TARGET}/spec" "${TARGET}/design/handoff"
  echo "# Test fixture" > "${TARGET}/README.md"
  echo "## Test spec" > "${TARGET}/spec/spec.md"
  cp tests/research-engine/fixtures/handoff-sample/index.html "${TARGET}/design/handoff/"
  cp tests/research-engine/fixtures/handoff-sample/meta.json "${TARGET}/design/handoff/"
  export RESEARCH_ENGINE_DESIGN_CACHE_ONLY=1
}

teardown() {
  rm -rf "${TARGET}"
}

@test "design script exists and is executable" {
  [ -x scripts/design_collect_only.sh ]
}

@test "design rejects missing slug" {
  run scripts/design_collect_only.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"slug required"* ]]
}

@test "design detects cached handoff and skips claude.ai automation" {
  run scripts/design_collect_only.sh "${SLUG}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"using existing handoff"* ]]
  [ -f "${TARGET}/design/handoff/index.html" ]
  [ -f "${TARGET}/design/handoff/meta.json" ]
  ls "${TARGET}/design/runs/" | grep -q '^[0-9]'
}
