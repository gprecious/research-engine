#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/yt_fetch.sh"
FIXTURE="$BATS_TEST_DIRNAME/../fixtures/yt_dlp_sample_dump.json"

setup() {
  TMPDIR_TEST="$(mktemp -d)"
}
teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "metadata subcommand with fixture yields JSON with id and title" {
  # --from-fixture reads the local JSON instead of calling yt-dlp
  run "$SCRIPT" metadata --from-fixture "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "dQw4w9WgXcQ"' > /dev/null
  echo "$output" | jq -e '.title == "Sample Video Title"' > /dev/null
}

@test "metadata subcommand picks caption language: original (en) first" {
  run "$SCRIPT" metadata --from-fixture "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.selected_caption_lang == "en"' > /dev/null
}

@test "metadata subcommand falls back to ko when original lang missing" {
  # override language to unsupported value
  local modified
  modified=$(jq '.language = "xx" | del(.subtitles)' "$FIXTURE")
  echo "$modified" > "$TMPDIR_TEST/modified.json"
  run "$SCRIPT" metadata --from-fixture "$TMPDIR_TEST/modified.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.selected_caption_lang == "ko"' > /dev/null
}

@test "missing subcommand errors" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "unknown subcommand errors" {
  run "$SCRIPT" nonsense
  [ "$status" -ne 0 ]
}
