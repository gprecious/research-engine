#!/usr/bin/env bats

setup() {
  SLUG="2026-05-23-design-test-fixture"
  TARGET="research/${SLUG}"
  mkdir -p "${TARGET}/spec" "${TARGET}/design/handoff"
  echo "# Test fixture" > "${TARGET}/README.md"
  echo "## Test spec" > "${TARGET}/spec/spec.md"
  cp tests/research-engine/fixtures/handoff-sample/index.html "${TARGET}/design/handoff/"
  cp tests/research-engine/fixtures/handoff-sample/meta.json "${TARGET}/design/handoff/"
  export RESEARCH_ENGINE_DESIGN_CACHE_ONLY=1
}

teardown() {
  rm -rf "research/2026-05-23-design-test-fixture"
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
  run scripts/design_collect_only.sh "2026-05-23-design-test-fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"using existing handoff"* ]]
  [ -f "research/2026-05-23-design-test-fixture/design/handoff/index.html" ]
  [ -f "research/2026-05-23-design-test-fixture/design/handoff/meta.json" ]
  ls research/2026-05-23-design-test-fixture/design/runs/ | grep -q '^[0-9]'
}
