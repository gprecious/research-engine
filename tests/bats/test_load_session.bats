#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/load_session.sh"
FIXTURE="$BATS_TEST_DIRNAME/../fixtures/sample-session"

@test "fails when research dir missing" {
  run "$SCRIPT" "sample-session" "/nonexistent/research"
  [ "$status" -ne 0 ]
}

@test "fails when slug dir missing" {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/research"
  run "$SCRIPT" "ghost" "$tmp/research"
  [ "$status" -ne 0 ]
  rm -rf "$tmp"
}

@test "fails when README.md missing" {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/research/x"
  echo '{}' > "$tmp/research/x/sources.json"
  run "$SCRIPT" "x" "$tmp/research"
  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
  rm -rf "$tmp"
}

@test "fails when sources.json missing" {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/research/x"
  echo '# ok' > "$tmp/research/x/README.md"
  run "$SCRIPT" "x" "$tmp/research"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sources.json"* ]]
  rm -rf "$tmp"
}

@test "emits JSON with slug, report_dir, readme, sources for valid session" {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/research"
  cp -r "$FIXTURE" "$tmp/research/sample-session"
  run "$SCRIPT" "sample-session" "$tmp/research"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.slug == "sample-session"' >/dev/null
  echo "$output" | jq -e '.report_dir | endswith("/sample-session")' >/dev/null
  echo "$output" | jq -e '.readme | contains("벤치마크")' >/dev/null
  echo "$output" | jq -e '.sources | length == 2' >/dev/null
  rm -rf "$tmp"
}
