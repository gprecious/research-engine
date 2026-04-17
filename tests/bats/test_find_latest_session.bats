#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/find_latest_session.sh"

setup() {
  TMPROOT="$(mktemp -d)"
  mkdir -p "$TMPROOT/research/2026-04-10-alpha"
  mkdir -p "$TMPROOT/research/2026-04-12-beta"
  mkdir -p "$TMPROOT/research/2026-04-14-gamma"
  # Make "beta" the newest by touching it last
  touch "$TMPROOT/research/2026-04-10-alpha"
  sleep 0.05
  touch "$TMPROOT/research/2026-04-14-gamma"
  sleep 0.05
  touch "$TMPROOT/research/2026-04-12-beta"
}
teardown() { rm -rf "$TMPROOT"; }

@test "returns slug of most recently touched session" {
  run "$SCRIPT" "$TMPROOT/research"
  [ "$status" -eq 0 ]
  [ "$output" = "2026-04-12-beta" ]
}

@test "errors when research dir missing" {
  run "$SCRIPT" "$TMPROOT/nonexistent"
  [ "$status" -ne 0 ]
}

@test "errors when research dir empty" {
  local empty
  empty="$(mktemp -d)"
  run "$SCRIPT" "$empty"
  [ "$status" -ne 0 ]
  rmdir "$empty"
}
