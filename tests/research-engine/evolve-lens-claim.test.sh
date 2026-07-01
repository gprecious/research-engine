#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  WORK=$(mktemp -d)
  mkdir -p "$WORK/agents/archive" "$WORK/research/_index" "$WORK/docs/dreams" "$WORK/scripts"
  cp -r "$REPO_ROOT/lib" "$WORK/"
  cp "$REPO_ROOT/scripts/evolve_run.sh" "$WORK/scripts/"
  chmod +x "$WORK/scripts/evolve_run.sh"
  cp "$REPO_ROOT/agents/lens-planner.md" "$WORK/agents/"
  cp "$REPO_ROOT/agents/claim-reviewer.md" "$WORK/agents/"
  export REPO_ROOT WORK
}
teardown() { rm -rf "$WORK"; }

@test "prepare extracts lens-planner lens-selection region" {
  cd "$WORK"
  out=$(bash scripts/evolve_run.sh prepare lens-planner lens-selection)
  echo "$out" | grep -q '"region_id": "lens-selection"'
  [ -n "$(echo "$out" | jq -r '.current_body')" ]
}
@test "prepare extracts claim-reviewer contradiction-detection region" {
  cd "$WORK"
  out=$(bash scripts/evolve_run.sh prepare claim-reviewer contradiction-detection)
  echo "$out" | grep -q '"region_id": "contradiction-detection"'
}
@test "apply writes a candidate for claim-reviewer missing-lens-detection" {
  cd "$WORK"
  echo '{"variants":[{"body":"NEW BODY","rationale":"x"}]}' > "$WORK/mut.json"
  path=$(bash scripts/evolve_run.sh apply claim-reviewer missing-lens-detection "$WORK/mut.json")
  grep -q "NEW BODY" "$path"
}
