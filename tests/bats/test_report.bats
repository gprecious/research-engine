#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../bench/report.py"
FIXTURE="$BATS_TEST_DIRNAME/../fixtures/bench-results/results.json"

setup() { TMPDIR_T="$(mktemp -d)"; cp "$FIXTURE" "$TMPDIR_T/results.json"; }
teardown() { rm -rf "$TMPDIR_T"; }

@test "renders report.md from results.json" {
  run "$SCRIPT" --results "$TMPDIR_T/results.json" --out "$TMPDIR_T/report.md"
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_T/report.md" ]
}

@test "report contains aggregate delta" {
  "$SCRIPT" --results "$TMPDIR_T/results.json" --out "$TMPDIR_T/report.md"
  grep -q "15.5" "$TMPDIR_T/report.md"
}

@test "report contains improvement opportunities section" {
  "$SCRIPT" --results "$TMPDIR_T/results.json" --out "$TMPDIR_T/report.md"
  grep -q -i "improvement opportunities" "$TMPDIR_T/report.md"
}

@test "report flags arxiv-sample as a candidate (small delta)" {
  "$SCRIPT" --results "$TMPDIR_T/results.json" --out "$TMPDIR_T/report.md"
  grep -q "arxiv-sample" "$TMPDIR_T/report.md"
}

@test "report contains limitations section" {
  "$SCRIPT" --results "$TMPDIR_T/results.json" --out "$TMPDIR_T/report.md"
  grep -q -i "limitations" "$TMPDIR_T/report.md"
}
