#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/slugify.sh"

@test "ASCII title" {
  run "$SCRIPT" "Attention Is All You Need"
  [ "$status" -eq 0 ]
  [ "$output" = "attention-is-all-you-need" ]
}

@test "strips punctuation" {
  run "$SCRIPT" "GPT-4, Explained!"
  [ "$status" -eq 0 ]
  [ "$output" = "gpt-4-explained" ]
}

@test "collapses whitespace" {
  run "$SCRIPT" "Multi   Space    Title"
  [ "$status" -eq 0 ]
  [ "$output" = "multi-space-title" ]
}

@test "keeps hangul as-is when present" {
  run "$SCRIPT" "전문가 혼합 구조 설명"
  [ "$status" -eq 0 ]
  [ "$output" = "전문가-혼합-구조-설명" ]
}

@test "truncates to 40 chars boundary" {
  run "$SCRIPT" "this is a very long title that absolutely must be truncated at the boundary"
  [ "$status" -eq 0 ]
  # 40 chars max, no trailing hyphen
  [ "${#output}" -le 40 ]
  [[ "$output" != *-  ]]
}

@test "empty input errors" {
  run "$SCRIPT" ""
  [ "$status" -ne 0 ]
}
