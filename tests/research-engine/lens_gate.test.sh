#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/lens_gate.sh"

@test "--no-lens forces off" {
  run "$SCRIPT" topic ok --no-lens
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .gate)" = "off" ]
  [ "$(echo "$output" | jq -r .reason)" = "disabled-flag" ]
}
@test "--lens forces on" {
  run "$SCRIPT" arxiv ok --lens
  [ "$(echo "$output" | jq -r .gate)" = "on" ]
  [ "$(echo "$output" | jq -r .reason)" = "forced" ]
}
@test "topic input turns lens on" {
  run "$SCRIPT" topic ok
  [ "$(echo "$output" | jq -r .gate)" = "on" ]
  [ "$(echo "$output" | jq -r .reason)" = "topic-mode" ]
}
@test "weak preview turns lens on" {
  run "$SCRIPT" youtube weak
  [ "$(echo "$output" | jq -r .gate)" = "on" ]
  [ "$(echo "$output" | jq -r .reason)" = "weak-preview" ]
}
@test "narrow input with ok preview stays off" {
  run "$SCRIPT" arxiv ok
  [ "$(echo "$output" | jq -r .gate)" = "off" ]
  [ "$(echo "$output" | jq -r .reason)" = "disabled-narrow-input" ]
}
