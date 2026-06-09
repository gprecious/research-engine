#!/usr/bin/env bash
# Wrapper over yt-dlp for the research-engine preview/full pipelines.
#
# Subcommands:
#   metadata <URL>                       — prints JSON with selected caption lang
#   metadata --from-fixture <PATH>       — same, but reads a local JSON dump (for tests)
#   media <URL> <DIR>                    — downloads the video once, prints {status, path, cached}
#   transcribe <FILE|URL> <DIR>          — Whisper transcription directly (no caption check)
#   captions <URL> <DIR> [--captions-only]
#                                         — downloads captions; falls back to Whisper when
#                                           absent unless --captions-only is given. Whisper
#                                           order: local (whisper.cpp / mlx-whisper /
#                                           openai-whisper, no key) → Groq → OpenAI.
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

load_key_var() {
  # $1 = env var name (e.g. GROQ_API_KEY); remaining args = .env files to scan.
  # Resolution order: process env → each file's "<VAR>=..." line (last wins per file).
  local var="$1"; shift
  if [[ -n "${!var:-}" ]]; then
    printf '%s' "${!var}"
    return 0
  fi
  local f value
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    value="$(grep -E "^${var}=" "$f" | tail -n1 | sed "s/^${var}=//; s/^\"//; s/\"\$//")"
    [[ -n "$value" ]] && { printf '%s' "$value"; return 0; }
  done
  return 1
}

load_groq_key() {
  load_key_var GROQ_API_KEY \
    "$HOME/.config/research-engine/groq.env" \
    "$HOME/.config/research-engine/.env"
}

load_openai_key() {
  load_key_var OPENAI_API_KEY \
    "$HOME/.config/research-engine/openai.env" \
    "$HOME/.config/research-engine/.env"
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

emit_whisper_ok() {
  local json="$1" vtt="$2" model="$3"
  write_vtt_from_whisper_json "$json" "$vtt"
  jq -n --arg vtt "$vtt" --arg json "$json" --arg model "$model" \
    '{status:"ok", transcript_source:"whisper", whisper_model:$model, transcript_vtt:$vtt, transcript_json:$json, failures:[]}'
}

# Local, key-free transcription. Whisper does NOT require a cloud key — this runs the
# model on-device. Backends, in priority order:
#   1. whisper.cpp (`whisper-cli`) — lightweight C++ binary, accepts mp3 directly, needs a
#      ggml model file. Preferred when present: no Python/torch stack.
#   2. mlx-whisper (Apple Silicon) / openai-whisper — Python; mlx auto-downloads the model.
#
# Knobs:
#   RESEARCH_ENGINE_WHISPER_DISABLE_LOCAL=1   disable all local backends
#   RESEARCH_ENGINE_WHISPER_DISABLE_CPP=1     skip whisper.cpp (use Python only)
#   RESEARCH_ENGINE_WHISPER_CPP_MODEL=<path>  explicit ggml model file for whisper.cpp
#   RESEARCH_ENGINE_WHISPER_MODEL=<hf repo>   mlx model (default below)
#   RESEARCH_ENGINE_WHISPER_OPENAI_MODEL=<n>  openai-whisper model name (default turbo)
#   RESEARCH_ENGINE_PYTHON=<python>           interpreter for the Python backends
WHISPER_LOCAL_MODEL_DEFAULT="mlx-community/whisper-large-v3-turbo"
WHISPER_CPP_MODEL_DIR_DEFAULT="$HOME/.config/research-engine/whisper-models"

# Resolves the Python interpreter for the mlx/openai backends:
#   RESEARCH_ENGINE_PYTHON → conventional research-engine venv → python3.
resolve_whisper_python() {
  if [[ -n "${RESEARCH_ENGINE_PYTHON:-}" ]]; then
    printf '%s' "${RESEARCH_ENGINE_PYTHON}"; return 0
  fi
  local venv_py="$HOME/.config/research-engine/whisper-venv/bin/python"
  [[ -x "$venv_py" ]] && { printf '%s' "$venv_py"; return 0; }
  command -v python3 >/dev/null 2>&1 && { printf 'python3'; return 0; }
  return 1
}

# Resolves a whisper.cpp ggml model file: explicit env → newest ggml-*.bin in the
# conventional model dir (turbo/large preferred). Non-zero if none found.
resolve_whisper_cpp_model() {
  if [[ -n "${RESEARCH_ENGINE_WHISPER_CPP_MODEL:-}" && -f "${RESEARCH_ENGINE_WHISPER_CPP_MODEL}" ]]; then
    printf '%s' "${RESEARCH_ENGINE_WHISPER_CPP_MODEL}"; return 0
  fi
  local d="${RESEARCH_ENGINE_WHISPER_CPP_MODEL_DIR:-$WHISPER_CPP_MODEL_DIR_DEFAULT}" m
  for m in "$d"/ggml-large-v3-turbo*.bin "$d"/ggml-large*.bin "$d"/ggml-*.bin; do
    [[ -f "$m" ]] && { printf '%s' "$m"; return 0; }
  done
  return 1
}

# Returns 0 if any local backend can be used (whisper.cpp w/ model, or a Python module).
whisper_local_available() {
  [[ "${RESEARCH_ENGINE_WHISPER_DISABLE_LOCAL:-0}" == "1" ]] && return 1
  if [[ "${RESEARCH_ENGINE_WHISPER_DISABLE_CPP:-0}" != "1" ]] \
     && command -v whisper-cli >/dev/null 2>&1 && resolve_whisper_cpp_model >/dev/null 2>&1; then
    return 0
  fi
  local py; py="$(resolve_whisper_python)" || return 1
  "$py" - <<'PY' 2>/dev/null
import importlib.util, sys
sys.exit(0 if (importlib.util.find_spec("mlx_whisper") or importlib.util.find_spec("whisper")) else 1)
PY
}

# Transcribes $1 (audio) locally, writing verbose_json-shaped output to $2 so it flows
# through emit_whisper_ok / write_vtt_from_whisper_json unchanged. Prints the backend id
# on success; non-zero exit on failure (caller falls through to cloud providers).
whisper_local() {
  local audio="$1" out="$2"
  # 1) whisper.cpp — light, no Python, reads mp3 directly.
  if [[ "${RESEARCH_ENGINE_WHISPER_DISABLE_CPP:-0}" != "1" ]] && command -v whisper-cli >/dev/null 2>&1; then
    local model
    if model="$(resolve_whisper_cpp_model)"; then
      local base="$out.cpp"
      if whisper-cli -m "$model" -f "$audio" -oj -of "$base" -l auto >/dev/null 2>&1 \
         && [[ -f "$base.json" ]] \
         && jq '{text: ([.transcription[].text] | add // ""),
                 language: (.result.language // ""),
                 segments: [.transcription[] | {start: (.offsets.from / 1000),
                                                 end: (.offsets.to / 1000), text: .text}]}' \
              "$base.json" > "$out" 2>/dev/null \
         && jq -e '.segments and (.segments | length > 0)' "$out" >/dev/null 2>&1; then
        printf 'whisper.cpp:%s' "$(basename "$model")"
        return 0
      fi
    fi
  fi
  # 2) Python backends: mlx-whisper (preferred) → openai-whisper.
  local py; py="$(resolve_whisper_python)" || return 1
  local mlx_model="${RESEARCH_ENGINE_WHISPER_MODEL:-${WHISPER_LOCAL_MODEL:-$WHISPER_LOCAL_MODEL_DEFAULT}}"
  local openai_model="${RESEARCH_ENGINE_WHISPER_OPENAI_MODEL:-turbo}"
  "$py" - "$audio" "$out" "$mlx_model" "$openai_model" <<'PY'
import sys, json, importlib.util
audio, out, mlx_model, openai_model = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
result, backend, errs = None, None, []
if importlib.util.find_spec("mlx_whisper"):
    try:
        import mlx_whisper
        result = mlx_whisper.transcribe(audio, path_or_hf_repo=mlx_model)
        backend = "mlx-whisper:" + mlx_model.split("/")[-1]
    except Exception as e:
        errs.append("mlx_whisper: %r" % e)
if result is None and importlib.util.find_spec("whisper"):
    try:
        import whisper
        result = whisper.load_model(openai_model).transcribe(audio)
        backend = "openai-whisper:" + openai_model
    except Exception as e:
        errs.append("openai-whisper: %r" % e)
if result is None:
    sys.stderr.write("; ".join(errs) + "\n")
    sys.exit(3)
segs = [{"start": float(s.get("start", 0) or 0), "end": float(s.get("end", 0) or 0),
         "text": s.get("text", "")} for s in (result.get("segments") or [])]
json.dump({"text": result.get("text", ""), "language": result.get("language", ""),
           "segments": segs, "backend": backend}, open(out, "w"))
print(backend)
PY
}

# Posts the extracted audio to an OpenAI-compatible transcription endpoint.
# `curl --retry` treats transient 408/429/5xx and timeouts as retryable, honoring
# the server's Retry-After header (curl >= 7.66) with exponential backoff in between.
# Returns 0 only on a 2xx response whose JSON carries a non-empty segments array.
whisper_request() {
  local endpoint="$1" model="$2" key="$3" audio="$4" out="$5"
  local code
  code="$(curl -sS \
    --retry 4 --retry-delay 2 --retry-max-time 120 --max-time 900 \
    -A "watch-skill/1.0 (+research-engine)" \
    -H "Authorization: Bearer $key" \
    -F "file=@$audio" \
    -F "model=$model" \
    -F "response_format=verbose_json" \
    -F "temperature=0" \
    -o "$out" \
    -w '%{http_code}' \
    "$endpoint" 2>/dev/null)" || code="000"
  [[ "$code" == 2?? ]] || return 1
  jq -e '.segments and (.segments | length > 0)' "$out" >/dev/null 2>&1
}

whisper_fallback() {
  local input="$1" dir="$2"
  mkdir -p "$dir"
  # 재사용 가드: 이전 실행의 whisper 산출물이 있으면 API 호출 없이 반환 (비용 중복 방지)
  if [[ -s "$dir/whisper.vtt" && -s "$dir/whisper.json" ]]; then
    jq -n --arg vtt "$dir/whisper.vtt" --arg json "$dir/whisper.json" \
      '{status:"ok", transcript_source:"whisper", whisper_model:"cached", transcript_vtt:$vtt, transcript_json:$json, failures:[]}'
    return 0
  fi
  local groq_key openai_key have_local=0
  groq_key="$(load_groq_key || true)"
  openai_key="$(load_openai_key || true)"
  if whisper_local_available; then have_local=1; fi
  # 사용 가능한 백엔드가 하나도 없을 때만 실패 — 로컬 설치 안내를 우선한다 (로컬 우선 원칙).
  if [[ "$have_local" -eq 0 && -z "$groq_key" && -z "$openai_key" ]]; then
    jq -n '{status:"partial", transcript_source:"none", failures:[{step:"whisper", error:"no whisper backend available — install whisper.cpp (brew install whisper-cpp + a ggml model in ~/.config/research-engine/whisper-models) or mlx-whisper, or set GROQ_API_KEY / OPENAI_API_KEY"}]}'
    return 0
  fi
  if ! extract_audio "$input" "$dir"; then
    jq -n '{status:"partial", transcript_source:"none", failures:[{step:"audio_extract", error:"ffmpeg audio extraction failed"}]}'
    return 0
  fi
  local response="$dir/whisper.json"
  local tried=()
  # 0순위 — 로컬 (키 불필요, 데이터가 기기 밖으로 나가지 않음; Apple Silicon은 mlx-whisper).
  if [[ "$have_local" -eq 1 ]]; then
    local backend
    if backend="$(whisper_local "$dir/audio.mp3" "$response" 2>"$dir/whisper_local.err")" \
         && jq -e '.segments and (.segments | length > 0)' "$response" >/dev/null 2>&1; then
      emit_whisper_ok "$response" "$dir/whisper.vtt" "$backend"
      return 0
    fi
    tried+=("local")
  fi
  # 1순위 Groq, 2순위 OpenAI — 호스팅 (curl 필요).
  if [[ -n "$groq_key" || -n "$openai_key" ]]; then
    command -v curl >/dev/null || die "curl not installed"
  fi
  if [[ -n "$groq_key" ]]; then
    if whisper_request "https://api.groq.com/openai/v1/audio/transcriptions" \
         "whisper-large-v3" "$groq_key" "$dir/audio.mp3" "$response"; then
      emit_whisper_ok "$response" "$dir/whisper.vtt" "groq:whisper-large-v3"
      return 0
    fi
    tried+=("groq")
  fi
  if [[ -n "$openai_key" ]]; then
    if whisper_request "https://api.openai.com/v1/audio/transcriptions" \
         "whisper-1" "$openai_key" "$dir/audio.mp3" "$response"; then
      emit_whisper_ok "$response" "$dir/whisper.vtt" "openai:whisper-1"
      return 0
    fi
    tried+=("openai")
  fi
  local tried_csv
  tried_csv="$(IFS=','; printf '%s' "${tried[*]}")"
  jq -n --arg tried "$tried_csv" \
    '{status:"partial", transcript_source:"none", failures:[{step:"whisper", error:("all whisper backends failed: " + $tried)}]}'
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

  media)
    [[ $# -eq 3 ]] || die "media needs <URL> <DIR>"
    url="$2"; dir="$3"
    command -v ffprobe >/dev/null || die "ffprobe not installed"
    mkdir -p "$dir"
    # 캐시 후보: .part(중단된 다운로드) 제외, find -print -quit 로 pipefail-안전하게 1개만
    existing="$(find "$dir" -maxdepth 1 -type f \( -name 'video.*' -o -name '*.mp4' -o -name '*.mkv' -o -name '*.webm' \) ! -name '*.part' -print -quit)"
    if [[ -n "$existing" ]]; then
      if ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$existing" 2>/dev/null | grep -q audio; then
        jq -n --arg path "$(abs_path "$existing")" '{status:"ok", path:$path, cached:true}'
        exit 0
      fi
      rm -f "$existing"   # 오디오 스트림 없음(병합 전 잔존물 등) — 깨진 캐시 제거 후 재다운로드
    fi
    # 임시 디렉토리에 받고 완료 후 move — 중단된 다운로드가 캐시 후보로 보이지 않게
    tmp_dir="$dir/.dl-tmp"
    rm -rf "$tmp_dir"; mkdir -p "$tmp_dir"
    if ! media_path="$(download_video "$url" "$tmp_dir")"; then
      die "media download failed: $url"
    fi
    [[ -n "$media_path" && -f "$media_path" ]] || die "media download failed: $url"
    final="$dir/$(basename "$media_path")"
    mv -f "$media_path" "$final"
    rm -rf "$tmp_dir"
    jq -n --arg path "$(abs_path "$final")" '{status:"ok", path:$path, cached:false}'
    ;;

  transcribe)
    [[ $# -eq 3 ]] || die "transcribe needs <FILE|URL> <DIR>"
    whisper_fallback "$2" "$3"
    ;;

  captions)
    shift
    captions_only=false
    positional=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --captions-only) captions_only=true; shift ;;
        *) positional+=("$1"); shift ;;
      esac
    done
    [[ ${#positional[@]} -eq 2 ]] || die "captions needs <URL> <DIR> [--captions-only]"
    url="${positional[0]}"; dir="${positional[1]}"
    mkdir -p "$dir"
    before_count="$(find "$dir" -maxdepth 1 -type f -name '*.vtt' ! -name 'whisper.vtt' | wc -l | tr -d ' ')"
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
    after_count="$(find "$dir" -maxdepth 1 -type f -name '*.vtt' ! -name 'whisper.vtt' | wc -l | tr -d ' ')"
    if [[ "$after_count" -gt "$before_count" || "$after_count" -gt 0 ]]; then
      mapfile -t vtts < <(find "$dir" -maxdepth 1 -type f -name '*.vtt' ! -name 'whisper.vtt' | sort)
      printf '%s\n' "${vtts[@]}" | jq -R -s '
        split("\n") | map(select(length > 0)) as $files
        | {status:"ok", transcript_source:"captions", caption_files:$files, failures:[]}
      '
    else
      if [[ "$captions_only" == true ]]; then
        # 교차 검증 전용 모드: 자막 부재는 실패가 아닌 정상 결과
        jq -n '{status:"ok", transcript_source:"none", caption_files:[], failures:[]}'
      else
        whisper_fallback "$url" "$dir"
      fi
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
    sed -n '2,13p' "$0"
    exit 1
    ;;

  *)
    die "unknown subcommand: $1"
    ;;
esac
