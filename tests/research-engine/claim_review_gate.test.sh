#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/claim_review_gate.sh"

@test "--no-review forces off" {
  run "$SCRIPT" 10 true --no-review
  [ "$(echo "$output" | jq -r .gate)" = "off" ]
  [ "$(echo "$output" | jq -r .reason)" = "disabled-flag" ]
}
@test "--review forces on" {
  run "$SCRIPT" 1 false --review
  [ "$(echo "$output" | jq -r .gate)" = "on" ]
  [ "$(echo "$output" | jq -r .reason)" = "forced" ]
}
@test "fewer than 2 sources turns off" {
  run "$SCRIPT" 1 true
  [ "$(echo "$output" | jq -r .gate)" = "off" ]
  [ "$(echo "$output" | jq -r .reason)" = "too-few-sources" ]
}
@test "lens-planned run turns review on" {
  run "$SCRIPT" 2 true
  [ "$(echo "$output" | jq -r .gate)" = "on" ]
  [ "$(echo "$output" | jq -r .reason)" = "lens-planned" ]
}
@test "four or more sources turns review on" {
  run "$SCRIPT" 4 false
  [ "$(echo "$output" | jq -r .gate)" = "on" ]
  [ "$(echo "$output" | jq -r .reason)" = "multi-source" ]
}
@test "narrow single-lens run stays off" {
  run "$SCRIPT" 3 false
  [ "$(echo "$output" | jq -r .gate)" = "off" ]
  [ "$(echo "$output" | jq -r .reason)" = "narrow-single-lens" ]
}
