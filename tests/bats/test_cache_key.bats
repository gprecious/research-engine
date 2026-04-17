#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/cache_key.sh"

@test "returns 12-char hex for URL" {
  run "$SCRIPT" "https://youtu.be/dQw4w9WgXcQ"
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 12 ]
  [[ "$output" =~ ^[0-9a-f]+$ ]]
}

@test "same URL yields same key" {
  out1=$("$SCRIPT" "https://example.com/foo")
  out2=$("$SCRIPT" "https://example.com/foo")
  [ "$out1" = "$out2" ]
}

@test "different URLs yield different keys" {
  out1=$("$SCRIPT" "https://example.com/foo")
  out2=$("$SCRIPT" "https://example.com/bar")
  [ "$out1" != "$out2" ]
}

@test "empty input errors" {
  run "$SCRIPT" ""
  [ "$status" -ne 0 ]
}
