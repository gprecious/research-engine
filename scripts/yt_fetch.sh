#!/usr/bin/env bash
# Wrapper over yt-dlp for the research-engine preview/full pipelines.
#
# Subcommands:
#   metadata <URL>                       — prints JSON with selected caption lang
#   metadata --from-fixture <PATH>       — same, but reads a local JSON dump (for tests)
#   captions <URL> <DIR>                 — downloads captions, falls back to Groq Whisper when absent
#   frames <URL|FILE> <DIR> [--start S] [--end E]
#                                         — extracts sampled JPEG frames + frames.json
#
# Output JSON schema for `metadata`:
# {
#   "id": "...", "title": "...", "description": "...", "uploader": "...",
#   "duration": <seconds>, "language": "<orig>",
#   "chapters": [...], "selected_caption_lang": "<code>",
#   "caption_langs_available": ["ko","en", ...]
# }
#
# Caption language priority: video original language → ko → en → first available.
set -euo pipefail

die() { echo "yt_fetch: $*" >&2; exit 2; }

MAX_FPS="${YT_FETCH_MAX_FPS:-2.0}"
MAX_FRAMES="${YT_FETCH_MAX_FRAMES:-54}"
FRAME_WIDTH="${YT_FETCH_FRAME_WIDTH:-512}"

yt_dlp_common_args() {
  printf '%s\n' "--ignore-config" "--extractor-args" "youtube:player_client=tv,web_safari,mweb"
  if [[ -n "${WATCH_COOKIES_BROWSER:-}" ]]; then
    printf '%s\n' "--cookies-from-browser" "$WATCH_COOKIES_BROWSER"
  fi
}

yt_dlp_fallback_args() {
  printf '%s\n' "--ignore-config" "--extractor-args" "youtube:player_client=web_safari,mweb"
  if [[ -n "${WATCH_COOKIES_BROWSER:-}" ]]; then
    printf '%s\n' "--cookies-from-browser" "$WATCH_COOKIES_BROWSER"
  fi
}

yt_dlp_default_args() {
  printf '%s\n' "--ignore-config"
  if [[ -n "${WATCH_COOKIES_BROWSER:-}" ]]; then
    printf '%s\n' "--cookies-from-browser" "$WATCH_COOKIES_BROWSER"
  fi
}

yt_dlp_capture_with_recovery() {
  local tmp_err
  tmp_err="$(mktemp)"
  local primary=()
  mapfile -t primary < <(yt_dlp_common_args)
  if yt-dlp "${primary[@]}" "$@" 2>"$tmp_err"; then
    rm -f "$tmp_err"
    return 0
  fi
  cat "$tmp_err" >&2
  rm -f "$tmp_err"
  local fallback=()
  mapfile -t fallback < <(yt_dlp_fallback_args)
  tmp_err="$(mktemp)"
  if yt-dlp "${fallback[@]}" "$@" 2>"$tmp_err"; then
    rm -f "$tmp_err"
    return 0
  fi
  cat "$tmp_err" >&2
  rm -f "$tmp_err"
  local defaults=()
  mapfile -t defaults < <(yt_dlp_default_args)
  yt-dlp "${defaults[@]}" "$@"
}

is_url() {
  [[ "$1" =~ ^https?:// ]]
}

abs_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
  else
    python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"
  fi
}

format_label() {
  local sec="${1%.*}"
  local h=$((sec / 3600))
  local m=$(((sec % 3600) / 60))
  local s=$((sec % 60))
  if (( h > 0 )); then
    printf '%02d:%02d:%02d' "$h" "$m" "$s"
  else
    printf '%02d:%02d' "$m" "$s"
  fi
}

media_duration() {
  local input="$1"
  if is_url "$input"; then
    yt_dlp_capture_with_recovery --skip-download --print "%(duration)s" "$input" | tail -n1
  else
    ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$input"
  fi
}

download_video() {
  local url="$1" dir="$2"
  mkdir -p "$dir"
  yt_dlp_capture_with_recovery \
    -f "18/bv*[height<=720]+ba/b[height<=720]/bv+ba/b" \
    --merge-output-format mp4 \
    -N 8 \
    -o "$dir/video.%(ext)s" \
    "$url" >/dev/null
  find "$dir" -maxdepth 1 -type f \( -name 'video.*' -o -name '*.mp4' -o -name '*.mkv' -o -name '*.webm' \) \
    | head -n1
}

auto_fps() {
  local dur="$1"
  awk -v dur="$dur" -v maxfps="$MAX_FPS" -v maxframes="$MAX_FRAMES" '
    function ceil(x){ return x == int(x) ? x : int(x) + 1 }
    function max(a,b){ return a > b ? a : b }
    function min(a,b){ return a < b ? a : b }
    BEGIN {
      if (dur <= 0) dur = 1
      if (dur <= 30) target = max(12, int(dur + 0.5))
      else if (dur <= 60) target = 32
      else if (dur <= 180) target = 42
      else if (dur <= 600) target = 48
      else target = maxframes
      target = min(target, maxframes)
      fps = target / dur
      if (fps > maxfps) fps = maxfps
      if (fps <= 0) fps = 0.1
      printf "%.6f", fps
    }'
}

load_groq_key() {
  if [[ -n "${GROQ_API_KEY:-}" ]]; then
    printf '%s' "$GROQ_API_KEY"
    return 0
  fi
  local f
  for f in "$HOME/.config/research-engine/groq.env" "$HOME/.config/research-engine/.env"; do
    [[ -f "$f" ]] || continue
    local value
    value="$(grep -E '^GROQ_API_KEY=' "$f" | tail -n1 | sed 's/^GROQ_API_KEY=//; s/^"//; s/"$//')"
    [[ -n "$value" ]] && { printf '%s' "$value"; return 0; }
  done
  return 1
}

extract_audio() {
  local input="$1" dir="$2"
  local media="$input"
  if is_url "$input"; then
    media="$(download_video "$input" "$dir/media")"
  fi
  [[ -n "$media" && -f "$media" ]] || return 1
  ffmpeg -nostdin -y -i "$media" -vn -ar 16000 -ac 1 -b:a 64k "$dir/audio.mp3" >/dev/null 2>&1
}

write_vtt_from_whisper_json() {
  local json="$1" vtt="$2"
  {
    printf 'WEBVTT\n\n'
    jq -r '
      def ts:
        . as $s
        | (($s / 3600) | floor) as $h
        | ((($s % 3600) / 60) | floor) as $m
        | ($s % 60) as $sec
        | "\($h | tostring | if length == 1 then "0"+. else . end):\($m | tostring | if length == 1 then "0"+. else . end):\($sec | tostring | split(".")[0] | if length == 1 then "0"+. else . end).000";
      (.segments // [])[]
      | ((.start // 0) | ts) + " --> " + ((.end // (.start + 2)) | ts) + "\n" + ((.text // "") | gsub("^\\s+|\\s+$"; "")) + "\n"
    ' "$json"
  } > "$vtt"
}

whisper_fallback() {
  local input="$1" dir="$2"
  mkdir -p "$dir"
  local key
  if ! key="$(load_groq_key)"; then
    jq -n '{status:"partial", transcript_source:"none", failures:[{step:"whisper", error:"GROQ_API_KEY not configured"}]}'
    return 0
  fi
  command -v curl >/dev/null || die "curl not installed"
  if ! extract_audio "$input" "$dir"; then
    jq -n '{status:"partial", transcript_source:"none", failures:[{step:"audio_extract", error:"ffmpeg audio extraction failed"}]}'
    return 0
  fi
  local response="$dir/whisper.json"
  if ! curl -sS \
    -A "watch-skill/1.0 (+research-engine)" \
    -H "Authorization: Bearer $key" \
    -F "file=@$dir/audio.mp3" \
    -F "model=whisper-large-v3" \
    -F "response_format=verbose_json" \
    -F "temperature=0" \
    "https://api.groq.com/openai/v1/audio/transcriptions" \
    -o "$response"; then
    jq -n '{status:"partial", transcript_source:"none", failures:[{step:"whisper", error:"Groq request failed"}]}'
    return 0
  fi
  if jq -e '.segments and (.segments | length > 0)' "$response" >/dev/null 2>&1; then
    write_vtt_from_whisper_json "$response" "$dir/whisper.vtt"
    jq -n --arg vtt "$dir/whisper.vtt" --arg json "$response" \
      '{status:"ok", transcript_source:"whisper", transcript_vtt:$vtt, transcript_json:$json, failures:[]}'
  else
    jq -n --arg json "$response" \
      '{status:"partial", transcript_source:"none", transcript_json:$json, failures:[{step:"whisper", error:"Groq response did not include segments"}]}'
  fi
}

pick_caption_lang() {
  # $1 = raw JSON dump
  jq -r '
    (.language // "") as $orig
    | ((.subtitles // {}) | keys) as $subs
    | ((.automatic_captions // {}) | keys) as $auto
    | ($subs + $auto | unique) as $all
    | if ($all | length) == 0 then ""
      elif ($all | index($orig)) then $orig
      elif ($all | index("ko")) then "ko"
      elif ($all | index("en")) then "en"
      else $all[0]
      end
  '
}

list_caption_langs() {
  jq -c '
    (((.subtitles // {}) | keys) + ((.automatic_captions // {}) | keys)) | unique
  '
}

case "${1:-}" in
  metadata)
    shift
    if [[ "${1:-}" == "--from-fixture" ]]; then
      shift
      [[ -f "${1:-}" ]] || die "fixture not found: ${1:-}"
      raw="$(cat "$1")"
    else
      [[ -n "${1:-}" ]] || die "metadata needs <URL> or --from-fixture <PATH>"
      raw="$(yt_dlp_capture_with_recovery --ignore-no-formats-error --skip-download --write-auto-sub --write-sub --dump-json "$1")"
    fi
    lang="$(printf '%s' "$raw" | pick_caption_lang)"
    langs="$(printf '%s' "$raw" | list_caption_langs)"
    printf '%s' "$raw" | jq \
      --arg lang "$lang" \
      --argjson langs "$langs" \
      '. + {selected_caption_lang: $lang, caption_langs_available: $langs}'
    ;;

  captions)
    [[ $# -eq 3 ]] || die "captions needs <URL> <DIR>"
    url="$2"; dir="$3"
    mkdir -p "$dir"
    before_count="$(find "$dir" -maxdepth 1 -type f -name '*.vtt' | wc -l | tr -d ' ')"
    # Download all available subs and auto-captions (orchestrator will pick).
    yt_dlp_capture_with_recovery \
      --ignore-no-formats-error \
      --skip-download \
      --write-auto-sub \
      --write-sub \
      --sub-format "vtt" \
      --convert-subs "vtt" \
      -o "$dir/%(id)s.%(ext)s" \
      "$url" >/dev/null 2>"$dir/captions.stderr" || true
    after_count="$(find "$dir" -maxdepth 1 -type f -name '*.vtt' | wc -l | tr -d ' ')"
    if [[ "$after_count" -gt "$before_count" || "$after_count" -gt 0 ]]; then
      mapfile -t vtts < <(find "$dir" -maxdepth 1 -type f -name '*.vtt' | sort)
      printf '%s\n' "${vtts[@]}" | jq -R -s '
        split("\n") | map(select(length > 0)) as $files
        | {status:"ok", transcript_source:"captions", caption_files:$files, failures:[]}
      '
    else
      whisper_fallback "$url" "$dir"
    fi
    ;;

  frames)
    [[ $# -ge 3 ]] || die "frames needs <URL|FILE> <DIR> [--start S] [--end E]"
    input="$2"; dir="$3"; shift 3
    start="0"; end=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --start)
          [[ -n "${2:-}" ]] || die "--start needs seconds"
          start="$2"; shift 2 ;;
        --end)
          [[ -n "${2:-}" ]] || die "--end needs seconds"
          end="$2"; shift 2 ;;
        *)
          die "unknown frames option: $1" ;;
      esac
    done
    command -v ffmpeg >/dev/null || die "ffmpeg not installed"
    command -v ffprobe >/dev/null || die "ffprobe not installed"
    mkdir -p "$dir"
    media="$input"
    if is_url "$input"; then
      media="$(download_video "$input" "$dir/media")"
    fi
    [[ -n "$media" && -f "$media" ]] || die "media not found: $input"
    total_duration="$(media_duration "$media")"
    duration="$(awk -v total="$total_duration" -v start="$start" -v end="$end" 'BEGIN {
      if (end == "" || end <= 0 || end > total) end = total
      d = end - start
      if (d <= 0) d = total
      printf "%.6f", d
    }')"
    fps="$(auto_fps "$duration")"
    rm -f "$dir"/frame_*.jpg "$dir/frames.json"
    args=(-nostdin -y -ss "$start")
    if [[ -n "$end" ]]; then
      args+=(-to "$end")
    fi
    args+=(-i "$media" -vf "fps=$fps,scale=$FRAME_WIDTH:-2" -frames:v "$MAX_FRAMES" -q:v 4 "$dir/frame_%04d.jpg")
    ffmpeg "${args[@]}" >/dev/null 2>"$dir/frames.stderr"
    mapfile -t frames < <(find "$dir" -maxdepth 1 -type f -name 'frame_*.jpg' | sort)
    [[ "${#frames[@]}" -gt 0 ]] || die "ffmpeg produced no frames; see $dir/frames.stderr"
    manifest='[]'
    i=0
    for frame in "${frames[@]}"; do
      t_sec="$(awk -v start="$start" -v idx="$i" -v fps="$fps" 'BEGIN { printf "%.3f", start + (idx / fps) }')"
      t_label="$(format_label "$t_sec")"
      frame_abs="$(abs_path "$frame")"
      manifest="$(jq -n \
        --argjson arr "$manifest" \
        --arg path "$frame_abs" \
        --argjson t "$t_sec" \
        --arg tlabel "$t_label" \
        '$arr + [{path:$path, t_sec:$t, t_label:$tlabel}]')"
      i=$((i + 1))
    done
    printf '%s\n' "$manifest" > "$dir/frames.json"
    jq -n \
      --argjson frames "$manifest" \
      --argjson fps "$fps" \
      --argjson duration "$duration" \
      '{status:"ok", fps:$fps, duration:$duration, frame_count:($frames|length), frames_json:"frames.json", frames:$frames}'
    ;;

  ""|-h|--help)
    sed -n '2,10p' "$0"
    exit 1
    ;;

  *)
    die "unknown subcommand: $1"
    ;;
esac
