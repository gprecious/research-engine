#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../bench/collect_metrics.sh"
FIXTURE="$BATS_TEST_DIRNAME/../fixtures/bench-output"

setup() {
  TMPDIR_T="$(mktemp -d)"
  cp "$FIXTURE/output.md" "$TMPDIR_T/output.md"
  cp "$FIXTURE/stderr.log" "$TMPDIR_T/stderr.log"
  cp "$FIXTURE/raw.json" "$TMPDIR_T/raw.json"
}
teardown() { rm -rf "$TMPDIR_T"; }

@test "writes meta.json with status ok on successful run" {
  run "$SCRIPT" "$TMPDIR_T" 1700000000 1700000612
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_T/meta.json" ]
  status_field=$(jq -r '.status' "$TMPDIR_T/meta.json")
  [ "$status_field" = "ok" ]
}

@test "computes wall_time_sec from start/end args" {
  "$SCRIPT" "$TMPDIR_T" 1700000000 1700000612
  wt=$(jq -r '.wall_time_sec' "$TMPDIR_T/meta.json")
  [ "$wt" = "612" ]
}

@test "counts numbered citations in output.md" {
  "$SCRIPT" "$TMPDIR_T" 1700000000 1700000612
  cc=$(jq -r '.citation_count' "$TMPDIR_T/meta.json")
  [ "$cc" -eq 10 ]
}

@test "counts external links in output.md" {
  "$SCRIPT" "$TMPDIR_T" 1700000000 1700000612
  ec=$(jq -r '.external_link_count' "$TMPDIR_T/meta.json")
  [ "$ec" -eq 4 ]
}

@test "marks status failed when output.md is missing" {
  rm "$TMPDIR_T/output.md"
  "$SCRIPT" "$TMPDIR_T" 1700000000 1700000612
  status_field=$(jq -r '.status' "$TMPDIR_T/meta.json")
  [ "$status_field" = "failed" ]
}

@test "extracts input/output tokens from raw.json" {
  "$SCRIPT" "$TMPDIR_T" 1700000000 1700000612
  in_tok=$(jq -r '.model_tokens.input' "$TMPDIR_T/meta.json")
  out_tok=$(jq -r '.model_tokens.output' "$TMPDIR_T/meta.json")
  [ "$in_tok" = "12340" ]
  [ "$out_tok" = "2100" ]
}

@test "model_tokens is null when raw.json is missing" {
  rm "$TMPDIR_T/raw.json"
  "$SCRIPT" "$TMPDIR_T" 1700000000 1700000612
  tokens=$(jq -r '.model_tokens' "$TMPDIR_T/meta.json")
  [ "$tokens" = "null" ]
}

@test "unique_citation_n_count counts distinct [n] markers (not total)" {
  "$SCRIPT" "$TMPDIR_T" 1700000000 1700000612
  uniq=$(jq -r '.unique_citation_n_count' "$TMPDIR_T/meta.json")
  cit=$(jq -r '.citation_count' "$TMPDIR_T/meta.json")
  # fixture has [1] [2] [3] markers — 3 unique IDs total
  [ "$uniq" -eq 3 ]
  [ "$cit" -ge "$uniq" ]
}
