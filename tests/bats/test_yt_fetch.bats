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

@test "frames subcommand extracts JPEGs and timestamp manifest from local video" {
  ffmpeg -f lavfi -i testsrc=size=320x180:rate=10 -t 4 \
    -pix_fmt yuv420p "$TMPDIR_TEST/sample.mp4" >/dev/null 2>&1

  run "$SCRIPT" frames "$TMPDIR_TEST/sample.mp4" "$TMPDIR_TEST/frames" --start 1 --end 3
  [ "$status" -eq 0 ]
  [ -s "$TMPDIR_TEST/frames/frame_0001.jpg" ]
  [ -s "$TMPDIR_TEST/frames/frames.json" ]
  file "$TMPDIR_TEST/frames/frame_0001.jpg" | grep -q "JPEG image data"
  jq -e 'length >= 2 and .[0].path and .[0].t_sec == 1 and .[0].t_label == "00:01"' \
    "$TMPDIR_TEST/frames/frames.json" >/dev/null
}

@test "metadata subcommand passes YouTube SABR player_client extractor args" {
  mkdir -p "$TMPDIR_TEST/bin"
  cat > "$TMPDIR_TEST/bin/yt-dlp" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$YT_DLP_ARGS_FILE"
cat "$YT_DLP_JSON_FILE"
SH
  chmod +x "$TMPDIR_TEST/bin/yt-dlp"

  YT_DLP_ARGS_FILE="$TMPDIR_TEST/args.txt" \
  YT_DLP_JSON_FILE="$FIXTURE" \
  PATH="$TMPDIR_TEST/bin:$PATH" \
  run "$SCRIPT" metadata "https://youtu.be/example"

  [ "$status" -eq 0 ]
  grep -q -- "--extractor-args youtube:player_client=tv,web_safari,mweb" "$TMPDIR_TEST/args.txt"
}

@test "metadata subcommand retries without tv client when primary YouTube client chain fails" {
  mkdir -p "$TMPDIR_TEST/bin"
  cat > "$TMPDIR_TEST/bin/yt-dlp" <<'SH'
#!/usr/bin/env bash
count_file="$TMPDIR_TEST/yt-dlp-count"
count="$(cat "$count_file" 2>/dev/null || echo 0)"
count=$((count + 1))
printf '%s' "$count" > "$count_file"
printf '%s\n' "$*" >> "$TMPDIR_TEST/args.txt"
if [ "$count" -eq 1 ]; then
  echo "ERROR: DRM protected" >&2
  exit 1
fi
cat "$YT_DLP_JSON_FILE"
SH
  chmod +x "$TMPDIR_TEST/bin/yt-dlp"

  TMPDIR_TEST="$TMPDIR_TEST" \
  YT_DLP_JSON_FILE="$FIXTURE" \
  PATH="$TMPDIR_TEST/bin:$PATH" \
  run "$SCRIPT" metadata "https://youtu.be/example"

  [ "$status" -eq 0 ]
  grep -q "youtube:player_client=tv,web_safari,mweb" "$TMPDIR_TEST/args.txt"
  grep -q "youtube:player_client=web_safari,mweb" "$TMPDIR_TEST/args.txt"
}

@test "captions subcommand reports partial when captions are absent and GROQ_API_KEY is unset" {
  mkdir -p "$TMPDIR_TEST/bin"
  cat > "$TMPDIR_TEST/bin/yt-dlp" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$TMPDIR_TEST/bin/yt-dlp"

  PATH="$TMPDIR_TEST/bin:$PATH" GROQ_API_KEY="" \
  run "$SCRIPT" captions "https://youtu.be/no-captions" "$TMPDIR_TEST/captions"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "partial" and .transcript_source == "none" and (.failures[]?.step == "whisper")' >/dev/null
}
