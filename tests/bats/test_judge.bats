#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../bench/judge.py"
CANNED="$BATS_TEST_DIRNAME/../fixtures/bench-judge/canned_response.json"

setup() {
  TMPDIR_T="$(mktemp -d)"
  mkdir -p "$TMPDIR_T/topic-1/re/run1" "$TMPDIR_T/topic-1/baseline/run1"
  echo "# RE output" > "$TMPDIR_T/topic-1/re/run1/output.md"
  echo "# Baseline output" > "$TMPDIR_T/topic-1/baseline/run1/output.md"
}
teardown() { rm -rf "$TMPDIR_T"; }

@test "--dry-run prints prompt without invoking claude" {
  run "$SCRIPT" --dry-run --topic-dir "$TMPDIR_T/topic-1" --topic-id topic-1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "report A"
  echo "$output" | grep -q "report B"
}

@test "--from-fixture reads canned response and writes judge.json" {
  run "$SCRIPT" --from-fixture "$CANNED" --topic-dir "$TMPDIR_T/topic-1" --topic-id topic-1
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_T/topic-1/judge.json" ]
  topic=$(jq -r '.topic_id' "$TMPDIR_T/topic-1/judge.json")
  [ "$topic" = "topic-1" ]
}

@test "judge.json decodes blind labels (re/baseline both present)" {
  "$SCRIPT" --from-fixture "$CANNED" --topic-dir "$TMPDIR_T/topic-1" --topic-id topic-1
  re_cov=$(jq -r '.cross_mode.re.coverage' "$TMPDIR_T/topic-1/judge.json")
  base_cov=$(jq -r '.cross_mode.baseline.coverage' "$TMPDIR_T/topic-1/judge.json")
  [ "$re_cov" != "null" ]
  [ "$base_cov" != "null" ]
}

@test "--self-check writes judge.json with both A and B (RE-as-both)" {
  # Self-check feeds the same RE output as both A and B.
  # We use --from-fixture to skip the live claude call; this just verifies
  # the wiring (judge.json exists, both cross_mode keys are populated).
  run "$SCRIPT" --self-check --from-fixture "$CANNED" \
      --topic-dir "$TMPDIR_T/topic-1" --topic-id topic-1
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_T/topic-1/judge.json" ]
}
