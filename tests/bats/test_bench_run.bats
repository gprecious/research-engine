#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../bench/run.sh"

@test "--check runs preflight without errors when env is sane" {
  run env NOTION_TOKEN= "$SCRIPT" --check
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "claude"
  echo "$output" | grep -q "yq"
  echo "$output" | grep -q "jq"
  echo "$output" | grep -q "topics.yaml"
}

@test "--check fails when NOTION_TOKEN is set" {
  run env NOTION_TOKEN=secret_xxx "$SCRIPT" --check
  [ "$status" -ne 0 ]
}

@test "--check fails when topics.yaml is missing" {
  TMP="$(mktemp -d)"
  run env NOTION_TOKEN= BENCH_REPO_ROOT_OVERRIDE="$TMP" "$SCRIPT" --check
  [ "$status" -ne 0 ]
  rm -rf "$TMP"
}
