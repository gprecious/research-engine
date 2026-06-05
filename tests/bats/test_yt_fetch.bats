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

@test "captions subcommand reports partial when captions are absent and no whisper key is set" {
  mkdir -p "$TMPDIR_TEST/bin"
  cat > "$TMPDIR_TEST/bin/yt-dlp" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$TMPDIR_TEST/bin/yt-dlp"

  # HOME isolation so ~/.config/research-engine/*.env keys can't leak in.
  HOME="$TMPDIR_TEST" \
  PATH="$TMPDIR_TEST/bin:$PATH" GROQ_API_KEY="" OPENAI_API_KEY="" \
  run "$SCRIPT" captions "https://youtu.be/no-captions" "$TMPDIR_TEST/captions"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "partial" and .transcript_source == "none" and (.failures[]?.step == "whisper")' >/dev/null
}

@test "captions falls back to OpenAI whisper-1 when Groq fails, with curl retry enabled" {
  # Media fixture carrying an audio track so extract_audio yields audio.mp3.
  ffmpeg -f lavfi -i sine=frequency=1000:duration=2 \
    -f lavfi -i testsrc=size=320x180:rate=10:duration=2 \
    -shortest -pix_fmt yuv420p "$TMPDIR_TEST/av.mp4" >/dev/null 2>&1

  mkdir -p "$TMPDIR_TEST/bin"
  # yt-dlp: emit no captions on the caption pass; copy the fixture on the download pass.
  cat > "$TMPDIR_TEST/bin/yt-dlp" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *--write-sub*) exit 0 ;;
esac
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
if [ -n "$out" ]; then
  target="${out/\%(ext)s/mp4}"
  mkdir -p "$(dirname "$target")"
  cp "$AV_FIXTURE" "$target"
fi
exit 0
SH
  chmod +x "$TMPDIR_TEST/bin/yt-dlp"

  # curl: Groq endpoint returns 429, OpenAI returns 200 with segments. Record args.
  cat > "$TMPDIR_TEST/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_ARGS_FILE"
out=""; url=""; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  case "$a" in https://*) url="$a" ;; esac
  prev="$a"
done
case "$url" in
  *groq.com*)   printf '{"error":{"message":"rate limited"}}' > "$out"; printf '429'; exit 0 ;;
  *openai.com*) printf '{"segments":[{"start":0,"end":1.5,"text":"hello"}]}' > "$out"; printf '200'; exit 0 ;;
esac
printf '000'; exit 0
SH
  chmod +x "$TMPDIR_TEST/bin/curl"

  HOME="$TMPDIR_TEST" \
  AV_FIXTURE="$TMPDIR_TEST/av.mp4" \
  CURL_ARGS_FILE="$TMPDIR_TEST/curl-args.txt" \
  PATH="$TMPDIR_TEST/bin:$PATH" \
  GROQ_API_KEY="gsk_test" OPENAI_API_KEY="sk_test" \
  run "$SCRIPT" captions "https://youtu.be/no-caps" "$TMPDIR_TEST/cap"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "ok" and .transcript_source == "whisper" and (.whisper_model | test("openai"))' >/dev/null
  [ -s "$TMPDIR_TEST/cap/whisper.vtt" ]
  grep -q -- "--retry" "$TMPDIR_TEST/curl-args.txt"
  grep -q "groq.com" "$TMPDIR_TEST/curl-args.txt"
  grep -q "openai.com" "$TMPDIR_TEST/curl-args.txt"
}

@test "media subcommand downloads once and reuses cached file on second call" {
  # 캐시 재사용 검증은 ffprobe 오디오 스트림 체크를 통과해야 하므로 실제 AV fixture 사용
  ffmpeg -f lavfi -i sine=frequency=1000:duration=1 \
    -f lavfi -i testsrc=size=320x180:rate=10:duration=1 \
    -shortest -pix_fmt yuv420p "$TMPDIR_TEST/src.mp4" >/dev/null 2>&1

  mkdir -p "$TMPDIR_TEST/bin"
  # yt-dlp mock: 호출 횟수를 기록하고, -o 타깃 위치에 fixture 를 복사
  cat > "$TMPDIR_TEST/bin/yt-dlp" <<'SH'
#!/usr/bin/env bash
count="$(cat "$COUNT_FILE" 2>/dev/null || echo 0)"
printf '%s' "$((count + 1))" > "$COUNT_FILE"
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
if [ -n "$out" ]; then
  target="${out/\%(ext)s/mp4}"
  mkdir -p "$(dirname "$target")"
  cp "$SRC_FIXTURE" "$target"
fi
exit 0
SH
  chmod +x "$TMPDIR_TEST/bin/yt-dlp"

  COUNT_FILE="$TMPDIR_TEST/count" SRC_FIXTURE="$TMPDIR_TEST/src.mp4" \
  PATH="$TMPDIR_TEST/bin:$PATH" \
  run "$SCRIPT" media "https://youtu.be/example" "$TMPDIR_TEST/media"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "ok" and .cached == false and (.path | endswith(".mp4"))' >/dev/null
  [ -s "$(echo "$output" | jq -r '.path')" ]

  # 두 번째 호출: 캐시 재사용 — yt-dlp 가 다시 호출되지 않아야 함
  COUNT_FILE="$TMPDIR_TEST/count" SRC_FIXTURE="$TMPDIR_TEST/src.mp4" \
  PATH="$TMPDIR_TEST/bin:$PATH" \
  run "$SCRIPT" media "https://youtu.be/example" "$TMPDIR_TEST/media"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "ok" and .cached == true' >/dev/null
  [ "$(cat "$TMPDIR_TEST/count")" = "1" ]
}

@test "media subcommand rejects .part and audio-less files as cache" {
  # 깨진 캐시 후보를 미리 배치: 오디오 없는 video-only 파일 + 중단된 .part
  ffmpeg -f lavfi -i testsrc=size=320x180:rate=10 -t 1 \
    -pix_fmt yuv420p "$TMPDIR_TEST/videoonly.mp4" >/dev/null 2>&1
  mkdir -p "$TMPDIR_TEST/media"
  cp "$TMPDIR_TEST/videoonly.mp4" "$TMPDIR_TEST/media/video.mp4"
  printf 'partial-bytes' > "$TMPDIR_TEST/media/video.mp4.part"

  # 정상 AV fixture + mock yt-dlp (위 테스트와 동일 mock)
  ffmpeg -f lavfi -i sine=frequency=1000:duration=1 \
    -f lavfi -i testsrc=size=320x180:rate=10:duration=1 \
    -shortest -pix_fmt yuv420p "$TMPDIR_TEST/src.mp4" >/dev/null 2>&1
  mkdir -p "$TMPDIR_TEST/bin"
  cat > "$TMPDIR_TEST/bin/yt-dlp" <<'SH'
#!/usr/bin/env bash
count="$(cat "$COUNT_FILE" 2>/dev/null || echo 0)"
printf '%s' "$((count + 1))" > "$COUNT_FILE"
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
if [ -n "$out" ]; then
  target="${out/\%(ext)s/mp4}"
  mkdir -p "$(dirname "$target")"
  cp "$SRC_FIXTURE" "$target"
fi
exit 0
SH
  chmod +x "$TMPDIR_TEST/bin/yt-dlp"

  COUNT_FILE="$TMPDIR_TEST/count" SRC_FIXTURE="$TMPDIR_TEST/src.mp4" \
  PATH="$TMPDIR_TEST/bin:$PATH" \
  run "$SCRIPT" media "https://youtu.be/example" "$TMPDIR_TEST/media"
  [ "$status" -eq 0 ]
  # 오디오 없는 캐시 후보는 거부되고 재다운로드 (cached:false, yt-dlp 1회)
  echo "$output" | jq -e '.status == "ok" and .cached == false' >/dev/null
  [ "$(cat "$TMPDIR_TEST/count")" = "1" ]
  # 결과 파일은 오디오 스트림 보유
  ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 \
    "$(echo "$output" | jq -r '.path')" | grep -q audio
}

@test "transcribe subcommand runs Whisper directly on a local media file" {
  # 오디오 트랙이 있는 로컬 미디어 → extract_audio 가 audio.mp3 생성 가능해야 함
  ffmpeg -f lavfi -i sine=frequency=1000:duration=2 \
    -f lavfi -i testsrc=size=320x180:rate=10:duration=2 \
    -shortest -pix_fmt yuv420p "$TMPDIR_TEST/av.mp4" >/dev/null 2>&1

  mkdir -p "$TMPDIR_TEST/bin"
  # curl mock: Groq 엔드포인트가 200 + segments 반환
  cat > "$TMPDIR_TEST/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
printf '{"segments":[{"start":0,"end":1.5,"text":"hello av-first"}]}' > "$out"
printf '200'
SH
  chmod +x "$TMPDIR_TEST/bin/curl"

  HOME="$TMPDIR_TEST" \
  PATH="$TMPDIR_TEST/bin:$PATH" GROQ_API_KEY="gsk_test" OPENAI_API_KEY="" \
  run "$SCRIPT" transcribe "$TMPDIR_TEST/av.mp4" "$TMPDIR_TEST/tr"

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "ok" and .transcript_source == "whisper" and (.whisper_model | test("groq"))' >/dev/null
  [ -s "$TMPDIR_TEST/tr/whisper.vtt" ]
  grep -q "hello av-first" "$TMPDIR_TEST/tr/whisper.vtt"
}

@test "transcribe subcommand reports partial when no whisper keys configured" {
  printf 'x' > "$TMPDIR_TEST/fake.mp4"
  # HOME 격리로 ~/.config/research-engine/*.env 키 누출 차단
  HOME="$TMPDIR_TEST" GROQ_API_KEY="" OPENAI_API_KEY="" \
  run "$SCRIPT" transcribe "$TMPDIR_TEST/fake.mp4" "$TMPDIR_TEST/tr"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "partial" and .transcript_source == "none" and (.failures[]?.step == "whisper")' >/dev/null
}

@test "transcribe reuses existing whisper output without calling the API" {
  ffmpeg -f lavfi -i sine=frequency=1000:duration=2 \
    -f lavfi -i testsrc=size=320x180:rate=10:duration=2 \
    -shortest -pix_fmt yuv420p "$TMPDIR_TEST/av.mp4" >/dev/null 2>&1

  mkdir -p "$TMPDIR_TEST/bin"
  cat > "$TMPDIR_TEST/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_ARGS_FILE"
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
printf '{"segments":[{"start":0,"end":1.5,"text":"first run"}]}' > "$out"
printf '200'
SH
  chmod +x "$TMPDIR_TEST/bin/curl"

  # 1차: API 호출로 whisper.vtt/json 생성
  HOME="$TMPDIR_TEST" CURL_ARGS_FILE="$TMPDIR_TEST/curl-args.txt" \
  PATH="$TMPDIR_TEST/bin:$PATH" GROQ_API_KEY="gsk_test" OPENAI_API_KEY="" \
  run "$SCRIPT" transcribe "$TMPDIR_TEST/av.mp4" "$TMPDIR_TEST/tr"
  [ "$status" -eq 0 ]
  [ -s "$TMPDIR_TEST/curl-args.txt" ]

  # 2차: 기존 산출물 재사용 — curl 미호출, whisper_model == "cached"
  rm -f "$TMPDIR_TEST/curl-args.txt"
  HOME="$TMPDIR_TEST" CURL_ARGS_FILE="$TMPDIR_TEST/curl-args.txt" \
  PATH="$TMPDIR_TEST/bin:$PATH" GROQ_API_KEY="gsk_test" OPENAI_API_KEY="" \
  run "$SCRIPT" transcribe "$TMPDIR_TEST/av.mp4" "$TMPDIR_TEST/tr"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "ok" and .transcript_source == "whisper" and .whisper_model == "cached"' >/dev/null
  [ ! -f "$TMPDIR_TEST/curl-args.txt" ]
}
