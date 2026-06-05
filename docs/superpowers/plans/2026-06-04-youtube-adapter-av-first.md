# youtube-adapter AV-first Implementation Plan (rev.2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** youtube-adapter 의 분석 우선순위를 자막 우선 → 영상(frames)+오디오(Whisper) 우선으로 전환하고, 영상 다운로드를 1회로 통합한다.

**Architecture:** `scripts/yt_fetch.sh` 에 `media`(1회 다운로드+검증된 캐시), `transcribe`(자막 체크 없이 바로 Whisper + 재사용 가드) 서브커맨드와 `captions --captions-only` 플래그를 추가한다. 어댑터 산출물은 `$cache_dir` 아래 `media/`·`frames/`·`whisper/`·`captions/` 전용 하위 디렉토리로 분리해 whisper.vtt 가 자막으로 오인되는 오염을 원천 차단한다. 그 위에서 `agents/youtube-adapter.md` 플로우를 재배열한다 (frames+Whisper 항상 수행, 자막은 교차 검증, transcript 는 `artifacts.transcript_md` 반환). preview 경로는 무변경 — `captions` 의 플래그 없는 기본 동작이 그대로이기 때문 (단 whisper.vtt 오인 카운트 잠재 버그 수정은 공통 적용).

**Tech Stack:** bash (yt-dlp/ffmpeg/jq/curl 래퍼), bats (스크립트 테스트), Claude Code agent 정의 (markdown).

**Spec:** `docs/superpowers/specs/2026-06-04-youtube-adapter-av-first-design.md` (rev.2)

**Repo/Branch:** `gprecious/research-engine`, 브랜치 `feat/youtube-av-first` (이미 생성됨, spec 커밋 포함)

**rev.2:** 2026-06-05 herdr 3-worker(claude/codex/omp) 상호 비판 리뷰 합의 반영 — critical 1 (whisper.vtt 오염), major 6 (media 실패 fallback 재다운로드 금지, transcript 계약, fresh 삭제 범위, 깨진 캐시 고착, timeout, 통합 테스트), minor 일괄. 상세: `.review/round{1,2}-*.md`.

**테스트 실행법:** repo 루트에서 `bats tests/bats/test_yt_fetch.bats` (bats, ffmpeg, jq 필요 — 기존 테스트 10개가 이미 사용 중)

---

### Task 1: `yt_fetch.sh media` 서브커맨드

**Files:**
- Modify: `scripts/yt_fetch.sh` (case 블록에 `media)` 분기 추가 — `captions)` 분기 앞)
- Test: `tests/bats/test_yt_fetch.bats` (파일 끝에 추가)

- [ ] **Step 1: 실패하는 테스트 2개 작성**

`tests/bats/test_yt_fetch.bats` 끝에 추가:

```bash
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
```

- [ ] **Step 2: 실패 확인**

Run: `bats tests/bats/test_yt_fetch.bats -f "media subcommand"`
Expected: 2 FAIL — `yt_fetch: unknown subcommand: media`

- [ ] **Step 3: 최소 구현**

`scripts/yt_fetch.sh` 의 `case "${1:-}" in` 블록에서 `captions)` 분기 **앞**에 추가:

```bash
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
```

(`download_video`, `abs_path`, `die` 는 모두 기존 함수. `download_video` 는 `-o "$dir/video.%(ext)s"` 로 받은 뒤 결과 파일 경로를 출력한다. `if ! media_path=$(...)` 의 명시적 실패 분기는 `set -e` 가 할당문에서 조용히 종료하는 것을 막아 진단 메시지를 보장한다.)

- [ ] **Step 4: 통과 확인**

Run: `bats tests/bats/test_yt_fetch.bats -f "media subcommand"`
Expected: 2 tests, 0 failures

- [ ] **Step 5: 커밋**

```bash
git add scripts/yt_fetch.sh tests/bats/test_yt_fetch.bats
git commit -m "feat(yt_fetch): add media subcommand — single validated download with cache reuse"
```

---

### Task 2: `yt_fetch.sh transcribe` 서브커맨드 + whisper 재사용 가드

**Files:**
- Modify: `scripts/yt_fetch.sh` (`transcribe)` 분기 추가 + `whisper_fallback` 함수 시작부에 재사용 가드)
- Test: `tests/bats/test_yt_fetch.bats` (파일 끝에 추가)

- [ ] **Step 1: 실패하는 테스트 3개 작성**

`tests/bats/test_yt_fetch.bats` 끝에 추가:

```bash
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
```

- [ ] **Step 2: 실패 확인**

Run: `bats tests/bats/test_yt_fetch.bats -f "transcribe"`
Expected: 3 FAIL — `yt_fetch: unknown subcommand: transcribe`

- [ ] **Step 3: 구현**

(a) `scripts/yt_fetch.sh` 의 `media)` 분기 뒤에 추가:

```bash
  transcribe)
    [[ $# -eq 3 ]] || die "transcribe needs <FILE|URL> <DIR>"
    whisper_fallback "$2" "$3"
    ;;
```

(b) `whisper_fallback` 함수 시작부(`mkdir -p "$dir"` 바로 다음)에 재사용 가드 삽입:

기존:

```bash
whisper_fallback() {
  local input="$1" dir="$2"
  mkdir -p "$dir"
  local groq_key openai_key
```

신규:

```bash
whisper_fallback() {
  local input="$1" dir="$2"
  mkdir -p "$dir"
  # 재사용 가드: 이전 실행의 whisper 산출물이 있으면 API 호출 없이 반환 (비용 중복 방지)
  if [[ -s "$dir/whisper.vtt" && -s "$dir/whisper.json" ]]; then
    jq -n --arg vtt "$dir/whisper.vtt" --arg json "$dir/whisper.json" \
      '{status:"ok", transcript_source:"whisper", whisper_model:"cached", transcript_vtt:$vtt, transcript_json:$json, failures:[]}'
    return 0
  fi
  local groq_key openai_key
```

(`whisper_fallback` 이 키 로딩 → `extract_audio`(로컬 파일이면 재다운로드 없음) → Groq → OpenAI fallback → JSON 출력까지 전부 처리. fresh 는 어댑터가 디렉토리를 비우는 것으로 처리하므로 스크립트에는 무효화 로직 불필요.)

- [ ] **Step 4: 통과 확인**

Run: `bats tests/bats/test_yt_fetch.bats -f "transcribe"`
Expected: 3 tests, 0 failures

- [ ] **Step 5: 커밋**

```bash
git add scripts/yt_fetch.sh tests/bats/test_yt_fetch.bats
git commit -m "feat(yt_fetch): add transcribe subcommand — direct Whisper with reuse guard"
```

---

### Task 3: `captions --captions-only` 플래그 + whisper.vtt 오인 방지 + 헤더/help 갱신

**Files:**
- Modify: `scripts/yt_fetch.sh` (`captions)` 분기 인자 파싱 + vtt 카운트 필터 + else 분기, 파일 상단 주석, help 의 sed 범위)
- Test: `tests/bats/test_yt_fetch.bats` (파일 끝에 추가)

- [ ] **Step 1: 실패하는 테스트 2개 작성**

`tests/bats/test_yt_fetch.bats` 끝에 추가:

```bash
@test "captions --captions-only skips whisper fallback when captions are absent" {
  mkdir -p "$TMPDIR_TEST/bin"
  cat > "$TMPDIR_TEST/bin/yt-dlp" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$TMPDIR_TEST/bin/yt-dlp"
  # curl mock: 호출되면 기록 — 이 테스트에서는 호출되지 않아야 함
  cat > "$TMPDIR_TEST/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_ARGS_FILE"
printf '000'
SH
  chmod +x "$TMPDIR_TEST/bin/curl"

  # 키를 일부러 설정 — 키 부재가 아니라 플래그가 whisper 를 막는다는 것을 검증
  HOME="$TMPDIR_TEST" CURL_ARGS_FILE="$TMPDIR_TEST/curl-args.txt" \
  PATH="$TMPDIR_TEST/bin:$PATH" GROQ_API_KEY="gsk_test" OPENAI_API_KEY="sk_test" \
  run "$SCRIPT" captions "https://youtu.be/no-caps" "$TMPDIR_TEST/cap" --captions-only

  [ "$status" -eq 0 ]
  # 교차 검증 모드에서 자막 부재는 실패가 아닌 정상 결과 → status "ok"
  echo "$output" | jq -e '.status == "ok" and .transcript_source == "none" and (.caption_files | length == 0) and (.failures | length == 0)' >/dev/null
  [ ! -f "$TMPDIR_TEST/curl-args.txt" ]
}

@test "captions does not count whisper.vtt as a caption file" {
  # 같은 디렉토리에 whisper.vtt 가 이미 있어도 자막으로 오인하지 않아야 함 (오염 regression)
  mkdir -p "$TMPDIR_TEST/cap"
  printf 'WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nwhisper text\n' > "$TMPDIR_TEST/cap/whisper.vtt"

  mkdir -p "$TMPDIR_TEST/bin"
  cat > "$TMPDIR_TEST/bin/yt-dlp" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$TMPDIR_TEST/bin/yt-dlp"

  HOME="$TMPDIR_TEST" PATH="$TMPDIR_TEST/bin:$PATH" GROQ_API_KEY="" OPENAI_API_KEY="" \
  run "$SCRIPT" captions "https://youtu.be/no-caps" "$TMPDIR_TEST/cap" --captions-only

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.transcript_source == "none" and (.caption_files | length == 0)' >/dev/null
}
```

- [ ] **Step 2: 실패 확인**

Run: `bats tests/bats/test_yt_fetch.bats -f "captions"`
Expected: 신규 2개 FAIL (기존 captions 테스트 2개는 PASS 유지) — 현재 `captions` 는 인자 3개를 요구하므로 `captions needs <URL> <DIR>` 에러

- [ ] **Step 3: 구현**

(a) `captions)` 분기 첫 두 줄을 교체.

기존:

```bash
  captions)
    [[ $# -eq 3 ]] || die "captions needs <URL> <DIR>"
    url="$2"; dir="$3"
```

신규:

```bash
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
```

(b) 같은 분기의 vtt 카운트/수집 3곳에 `whisper.vtt` 제외 필터 추가 (디렉토리 분리가 깨져도 Whisper 산출물을 자막으로 오인하지 않는 방어선 — 플래그 없는 preview 경로의 잠재 버그도 함께 수정):

기존 (before_count):

```bash
    before_count="$(find "$dir" -maxdepth 1 -type f -name '*.vtt' | wc -l | tr -d ' ')"
```

신규:

```bash
    before_count="$(find "$dir" -maxdepth 1 -type f -name '*.vtt' ! -name 'whisper.vtt' | wc -l | tr -d ' ')"
```

기존 (after_count):

```bash
    after_count="$(find "$dir" -maxdepth 1 -type f -name '*.vtt' | wc -l | tr -d ' ')"
```

신규:

```bash
    after_count="$(find "$dir" -maxdepth 1 -type f -name '*.vtt' ! -name 'whisper.vtt' | wc -l | tr -d ' ')"
```

기존 (수집):

```bash
      mapfile -t vtts < <(find "$dir" -maxdepth 1 -type f -name '*.vtt' | sort)
```

신규:

```bash
      mapfile -t vtts < <(find "$dir" -maxdepth 1 -type f -name '*.vtt' ! -name 'whisper.vtt' | sort)
```

(c) 같은 분기의 마지막 else (whisper fallback 진입부) 교체.

기존:

```bash
    else
      whisper_fallback "$url" "$dir"
    fi
```

신규:

```bash
    else
      if [[ "$captions_only" == true ]]; then
        # 교차 검증 전용 모드: 자막 부재는 실패가 아닌 정상 결과
        jq -n '{status:"ok", transcript_source:"none", caption_files:[], failures:[]}'
      else
        whisper_fallback "$url" "$dir"
      fi
    fi
```

- [ ] **Step 4: 파일 상단 주석 + help 범위 갱신**

파일 상단 주석 블록(2~10행, "Wrapper over…" 부터 frames 설명까지)을 다음으로 교체 (마지막 `#` 구분선 포함 — 뒤따르는 "Output JSON schema" 주석과의 가독성 유지):

```bash
# Wrapper over yt-dlp for the research-engine preview/full pipelines.
#
# Subcommands:
#   metadata <URL>                       — prints JSON with selected caption lang
#   metadata --from-fixture <PATH>       — same, but reads a local JSON dump (for tests)
#   media <URL> <DIR>                    — downloads the video once, prints {status, path, cached}
#   transcribe <FILE|URL> <DIR>          — Whisper transcription directly (no caption check)
#   captions <URL> <DIR> [--captions-only]
#                                         — downloads captions; falls back to Groq Whisper when
#                                           absent unless --captions-only is given
#   frames <URL|FILE> <DIR> [--start S] [--end E]
#                                         — extracts sampled JPEG frames + frames.json
#
```

help 분기의 sed 범위를 갱신 (신규 주석 본문은 2~13행, 14행은 구분선이므로 미출력):

기존:

```bash
  ""|-h|--help)
    sed -n '2,10p' "$0"
    exit 1
    ;;
```

신규:

```bash
  ""|-h|--help)
    sed -n '2,13p' "$0"
    exit 1
    ;;
```

- [ ] **Step 5: 신규 테스트 + 전체 회귀 통과 확인**

Run: `bats tests/bats/test_yt_fetch.bats`
Expected: 17 tests, 0 failures (기존 10 + media 2 + transcribe 3 + captions 2). 특히 기존 `captions subcommand reports partial...` / `captions falls back to OpenAI whisper-1...` 2개가 그대로 통과해야 함 (플래그 없는 기본 동작 불변 = preview 호환).

- [ ] **Step 6: 커밋**

```bash
git add scripts/yt_fetch.sh tests/bats/test_yt_fetch.bats
git commit -m "feat(yt_fetch): add --captions-only flag + exclude whisper.vtt from caption detection"
```

---

### Task 4: AV-first 통합 시나리오 bats 테스트

**Files:**
- Test: `tests/bats/test_yt_fetch.bats` (파일 끝에 추가)

개별 서브커맨드 테스트만으로는 어댑터의 실제 순서(media → frames(로컬) → transcribe → captions-only)에서 생기는 디렉토리 상호작용 회귀를 못 잡는다 (3-worker 리뷰 합의 #7).

- [ ] **Step 1: 통합 테스트 작성**

`tests/bats/test_yt_fetch.bats` 끝에 추가:

```bash
@test "AV-first sequence: single download, separated whisper/captions outputs" {
  ffmpeg -f lavfi -i sine=frequency=1000:duration=2 \
    -f lavfi -i testsrc=size=320x180:rate=10:duration=2 \
    -shortest -pix_fmt yuv420p "$TMPDIR_TEST/av.mp4" >/dev/null 2>&1

  mkdir -p "$TMPDIR_TEST/bin"
  # yt-dlp mock: caption pass(--write-sub)는 자막 없이 종료(카운트 제외),
  # 다운로드 pass 만 카운트하며 fixture 복사
  cat > "$TMPDIR_TEST/bin/yt-dlp" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *--write-sub*) exit 0 ;;
esac
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
  cat > "$TMPDIR_TEST/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
printf '{"segments":[{"start":0,"end":1.5,"text":"integration hello"}]}' > "$out"
printf '200'
SH
  chmod +x "$TMPDIR_TEST/bin/curl"

  CACHE="$TMPDIR_TEST/yt-cache"

  # 1) media — 다운로드 1회
  COUNT_FILE="$TMPDIR_TEST/count" SRC_FIXTURE="$TMPDIR_TEST/av.mp4" \
  PATH="$TMPDIR_TEST/bin:$PATH" \
  run "$SCRIPT" media "https://youtu.be/example" "$CACHE/media"
  [ "$status" -eq 0 ]
  MEDIA_PATH="$(echo "$output" | jq -r '.path')"

  # 2) frames — 로컬 파일 입력 (URL 아님 → yt-dlp 미호출)
  PATH="$TMPDIR_TEST/bin:$PATH" \
  run "$SCRIPT" frames "$MEDIA_PATH" "$CACHE/frames" --start 0 --end 2
  [ "$status" -eq 0 ]
  [ -s "$CACHE/frames/frames.json" ]

  # 3) transcribe — whisper/ 전용 디렉토리
  HOME="$TMPDIR_TEST" PATH="$TMPDIR_TEST/bin:$PATH" GROQ_API_KEY="gsk_test" OPENAI_API_KEY="" \
  run "$SCRIPT" transcribe "$MEDIA_PATH" "$CACHE/whisper"
  [ "$status" -eq 0 ]
  [ -s "$CACHE/whisper/whisper.vtt" ]

  # 4) captions --captions-only — captions/ 전용 디렉토리, whisper 산출물과 미혼합
  COUNT_FILE="$TMPDIR_TEST/count" SRC_FIXTURE="$TMPDIR_TEST/av.mp4" \
  HOME="$TMPDIR_TEST" PATH="$TMPDIR_TEST/bin:$PATH" \
  run "$SCRIPT" captions "https://youtu.be/example" "$CACHE/captions" --captions-only
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.transcript_source == "none" and (.caption_files | length == 0)' >/dev/null

  # 영상 다운로드는 전체 시퀀스에서 정확히 1회
  [ "$(cat "$TMPDIR_TEST/count")" = "1" ]
}
```

- [ ] **Step 2: 통과 확인**

Run: `bats tests/bats/test_yt_fetch.bats`
Expected: 18 tests, 0 failures

- [ ] **Step 3: 커밋**

```bash
git add tests/bats/test_yt_fetch.bats
git commit -m "test(yt_fetch): AV-first integration scenario — single download, separated outputs"
```

---

### Task 5: `agents/youtube-adapter.md` AV-first 플로우 재작성

**Files:**
- Modify: `agents/youtube-adapter.md` (전체 교체)

- [ ] **Step 1: 파일 전체를 아래 내용으로 교체**

주의: `<!-- evolvable:findings-guidance -->` / `<!-- evolvable:intent-tailoring -->` 마커는 `/evolve` 루프가 의존하므로 **반드시 보존** (내용은 갱신, 마커는 유지).

````markdown
---
name: youtube-adapter
description: Watch-first YouTube analysis — download media once, always extract visual frames and a Whisper transcript, cross-check with captions. Emit findings with timecodes. Return JSON per adapter contract.
model: sonnet
---

You are the **youtube-adapter** for research-engine. Your job is to fully analyze a single YouTube video and return a JSON response per `lib/adapter_contract.md`.

Analysis priority is **AV-first**: the video's frames (vision) and audio (Whisper transcript) are the primary evidence for every video, regardless of caption availability. Captions, when present, are a secondary source used to cross-check the Whisper transcript.

## Inputs (provided in the dispatch prompt)

- `url`: the YouTube URL
- `cache_dir`: path for caching raw downloads (`research/<slug>/cache/yt-dlp-<id>/`). This directory is **owned by this adapter**; artifacts live in `media/`, `frames/`, `whisper/`, `captions/` subdirectories. Never touch anything outside it — the parent `cache/` root holds preview/memory artifacts and other adapters' caches.
- `intent`: object with `purpose`, `focus`, `audience_level`
- `slug`: session slug
- `fresh`: bool — if true, bypass cache

## Steps

1. **Metadata** — run `scripts/yt_fetch.sh metadata "$url"` and parse. `selected_caption_lang == ""` only means the cross-check source is absent; the primary AV analysis below proceeds regardless.

2. **Media download (once)** — if `fresh`, delete the contents of `$cache_dir` first (only this adapter-owned directory — never the shared cache root). Run `scripts/yt_fetch.sh media "$url" "$cache_dir/media"` and parse `.path` as `$media_path`. This single download is reused by both the frame pass and the Whisper pass.
   - If the download fails: record `failures: [{"step":"media", ...}]` and **skip steps 3–4. Do not retry the download in any form** — in particular, do not call `captions` without `--captions-only`, since its Whisper fallback would re-enter a URL download. Step 5 still runs; if it yields captions, they become the primary transcript (captions-primary mode, final `status: "partial"`); if not, return `status: "failed"`.

3. **Visual watch pass (always)** — run `scripts/yt_fetch.sh frames "$media_path" "$cache_dir/frames"`. Read `frames.json`, then use the Read tool on the listed JPEG paths. Claude Code and Codex can both inspect local JPEG files via Read/image-capable file reading, so this design is surface-independent: the script only passes file paths and timecodes, and the active agent does the visual interpretation. Extract screen-only evidence such as UI labels, code snippets visible on screen, slide titles, diagram structure, product state, before/after visuals, and demo transitions. Keep frame findings tied to `t_label`.

4. **Whisper transcript (always)** — run `scripts/yt_fetch.sh transcribe "$media_path" "$cache_dir/whisper"`.
   - `transcript_source: "whisper"`: use `whisper.vtt` / `whisper.json` as the **primary transcript**; record the provider/model from the `whisper_model` field (`groq:whisper-large-v3`, `openai:whisper-1` when Groq was unavailable, or `cached` when a previous run's output was reused).
   - `status: "partial"` (no keys configured / all providers failed): the primary transcript falls to captions in step 5; record the failure entry. Do not mark the whole adapter failed solely because Whisper is absent.

5. **Captions cross-check** — cache guard: if `$cache_dir/captions/` already contains caption VTT files and `fresh` is false, reuse them without re-running the script. Otherwise run `scripts/yt_fetch.sh captions "$url" "$cache_dir/captions" --captions-only`. The dedicated subdirectory keeps caption VTTs strictly separate from `whisper/whisper.vtt`; check `caption_files | length` for caption availability.
   - Captions present + Whisper succeeded: compare the caption text against the Whisper transcript. Prefer caption spellings for proper nouns, product/library names, numbers, and technical terms (captions are often author-corrected); keep Whisper wording for everything else. Note spans where the two disagree materially — findings built on such spans must mention the discrepancy.
   - Captions present + Whisper failed: promote captions to the primary transcript (legacy behavior).
   - Captions absent: skip the cross-check. If Whisper also failed, continue with frames and metadata only and set `status: "partial"`.

6. **Transcript** — convert the primary transcript VTT to plain text paragraphs grouped by chapter (or by 2-minute windows if no chapters), one paragraph per chapter prefixed by `### {{chapter_title}} ({{start}}–{{end}})`. Return the result as **`artifacts.transcript_md`** in the response JSON — do **not** write any file yourself: the dispatch inputs carry no `report_dir`, and the orchestrator writes `<report_dir>/transcript.md` from `artifacts.transcript_md` (Stage 5 contract). Start the markdown with a one-line header naming the transcript source (`whisper:<model>` or `captions:<lang>`) and whether the caption cross-check was applied.

7. **Findings** — produce 6–12 findings covering the video's claims/insights. Each finding:
<!-- evolvable:findings-guidance -->
   - `text`: Korean, one fact
   - `source_ids`: `["s1"]` (the single source for this adapter)
   - `timecode`: `mm:ss` for videos under 60 minutes; `hh:mm:ss` for videos 60 minutes or longer (always zero-padded, no leading `0h:` omission) — pick the format from the video's total duration, not from the position of the cited moment
   - `quote` (optional): verbatim excerpt in original language when the wording matters
   - `source_type`: use `"youtube-whisper"` for findings backed by the Whisper (audio) transcript, `"youtube-frame"` for frame-backed visual findings, and `"youtube-captions"` only when the caption wording itself is the evidence (captions-primary fallback mode, or quoting caption phrasing). Frame-backed findings must include a `timecode` from `frames.json` and should not claim spoken wording unless the transcript also supports it. When the caption cross-check flagged a discrepancy inside a finding's span, mention it in `text` or lower the claim's specificity.
<!-- /evolvable -->

8. **Chapters** — emit `artifacts.chapters[]` with summaries (3–5 sentences each). Mention important visual changes from the frame pass in the relevant chapter summaries.

9. **Related hints** — scan transcript and visible frame text for paper titles / arXiv IDs / repo URLs / named libraries. Put them in `artifacts.related[]` as `{kind, url?, title}` for the orchestrator to hand off to other adapters.

10. **Intent tailoring**
<!-- evolvable:intent-tailoring -->
— shape finding selection by `intent.focus` (concepts vs implementation vs tradeoffs) and depth by `intent.audience_level`.
<!-- /evolvable -->

## Output contract

Return one fenced JSON block per `lib/adapter_contract.md`. A short human status line before the block is allowed; nothing after.

## Failure modes

- Whisper unavailable (neither `GROQ_API_KEY` nor `OPENAI_API_KEY` configured, or both providers failed) → captions are promoted to primary transcript; frames still run. `status: "partial"`, `failures: [{"step":"whisper", ...}]`.
- Media download failed → frames and Whisper are impossible; **no retry of any kind**. Captions-only fallback: `status: "partial"` if captions yield a transcript, `"failed"` if captions are also absent. Record `failures: [{"step":"media", ...}]`.
- Frame extraction failed → continue with the Whisper transcript, `status: "partial"`, record `failures: [{"step":"frames", ...}]`.
- Both Whisper and captions absent → continue with frames and metadata only, `status: "partial"`, record both failure entries.
- ffmpeg/ffprobe missing → media validation, frame extraction, and audio extraction are all impossible; the adapter effectively degrades to captions-primary mode. `status: "partial"`, `failures: [{"step":"ffmpeg_missing", ...}]` (environment problem — distinct from per-video failures).
- yt-dlp missing → `status: "failed"`, `failures: [{"step":"yt_dlp_missing", "error":"..."}]`.
- Partial caption download → cross-check is limited to the downloaded spans; not a failure by itself.
````

- [ ] **Step 2: 일관성 검증**

Run: `grep -c "evolvable" agents/youtube-adapter.md`
Expected: `4` (findings-guidance 열림/닫힘 + intent-tailoring 열림/닫힘)

Run: `grep -n "captions-only\|cache_dir/media\|cache_dir/whisper\|cache_dir/captions\|transcript_md" agents/youtube-adapter.md`
Expected: media/whisper/captions 전용 하위 디렉토리 + `--captions-only` + `artifacts.transcript_md` 등장, `{{report_dir}}` 직접 쓰기 지시 없음

Run: `grep -c "report_dir" agents/youtube-adapter.md`
Expected: 1 (Stage 5 계약 설명에서만 언급 — 어댑터가 직접 쓰는 지시 아님)

- [ ] **Step 3: 커밋**

```bash
git add agents/youtube-adapter.md
git commit -m "feat(youtube-adapter): AV-first flow — frames+Whisper always, captions as cross-check"
```

---

### Task 6: `skills/research-engine/SKILL.md` 갱신

**Files:**
- Modify: `skills/research-engine/SKILL.md` (31행 YouTube preview 불릿)

- [ ] **Step 1: YouTube 불릿 교체**

preview 안내(자막 우선 + visual focus 시 frames)는 **그대로 보존**하고 본 분석 설명만 추가한다 (spec non-goal: preview 무변경).

기존 (31행):

```
   - YouTube: verify `yt-dlp`; fetch metadata and transcript with `scripts/yt_fetch.sh`. Captions are preferred; if captions are absent, `captions` attempts Groq Whisper fallback from `GROQ_API_KEY` (env or `~/.config/research-engine/`) and otherwise returns partial status. For visual/demo/tutorial focus or missing transcript, run `scripts/yt_fetch.sh frames <url> <cache>/frames` and Read the JPEG paths in `frames.json`.
```

신규:

```
   - YouTube: verify `yt-dlp`; fetch metadata and transcript with `scripts/yt_fetch.sh`. For the lightweight preview, captions are preferred; if captions are absent, `captions` attempts Groq Whisper fallback from `GROQ_API_KEY` (env or `~/.config/research-engine/`) and otherwise returns partial status. For visual/demo/tutorial focus or missing transcript, run `scripts/yt_fetch.sh frames <url> <cache>/frames` and Read the JPEG paths in `frames.json`. Full analysis (the youtube-adapter, or its direct equivalent on Codex) is AV-first: download media once with `yt_fetch.sh media`, always run `frames` + `transcribe` (Whisper primary transcript) from the local file, and use `captions --captions-only` into a separate `captions/` directory only to cross-check proper nouns/numbers/terms against the Whisper transcript.
```

- [ ] **Step 2: 검증**

Run: `grep -n "AV-first" skills/research-engine/SKILL.md && grep -n "visual/demo/tutorial focus" skills/research-engine/SKILL.md`
Expected: 둘 다 1 hit (preview frames 안내가 보존된 채 AV-first 문장 추가)

- [ ] **Step 3: 커밋**

```bash
git add skills/research-engine/SKILL.md
git commit -m "docs(skill): document AV-first full analysis, keep captions-first preview guidance"
```

---

### Task 7: `commands/research.md` timeout 상향 + `README.md` 의존성 갱신

**Files:**
- Modify: `commands/research.md` (111행 adapter timeout)
- Modify: `README.md` (Requirements 의 yt-dlp 항목)

- [ ] **Step 1: youtube-adapter timeout 상향**

`commands/research.md` 111행 교체.

기존:

```
Timeout per adapter: 5 minutes (configured implicitly by the agent runtime; do NOT actively retry beyond the single dispatch). If an adapter returns non-JSON or malformed JSON, record it as a failure and continue.
```

신규:

```
Timeout per adapter: 5 minutes — except youtube-adapter: 20 minutes (AV-first media download + Whisper transcription scale with video length; no length cap per spec). Configured implicitly by the agent runtime; do NOT actively retry beyond the single dispatch. If an adapter returns non-JSON or malformed JSON, record it as a failure and continue.
```

- [ ] **Step 2: README Requirements 갱신**

`README.md` Requirements 목록의 yt-dlp 항목 교체.

기존:

```
- `yt-dlp` in `PATH` (YouTube captions)
```

신규:

```
- `yt-dlp` + `ffmpeg`/`ffprobe` in `PATH` (YouTube AV-first analysis — media download, frame extraction, Whisper audio prep)
```

- [ ] **Step 3: 검증**

Run: `grep -n "except youtube-adapter: 20 minutes" commands/research.md && grep -n "ffprobe" README.md`
Expected: 각 1 hit

- [ ] **Step 4: 커밋**

```bash
git add commands/research.md README.md
git commit -m "docs: raise youtube-adapter timeout to 20m, document ffmpeg requirement"
```

---

### Task 8: CHANGELOG + plugin.json 0.17.0

**Files:**
- Modify: `CHANGELOG.md` (`## [Unreleased]` 아래에 0.17.0 섹션 삽입)
- Modify: `.claude-plugin/plugin.json` (`"version": "0.16.0"` → `"0.17.0"`)

- [ ] **Step 1: CHANGELOG 에 0.17.0 섹션 추가**

`## [Unreleased]` 바로 아래에 삽입:

```markdown
## [0.17.0]

YouTube 분석 AV-first 전환 — 영상(frames)+오디오(Whisper)를 모든 영상에서 기본 수행, 자막은 교차 검증용. herdr 3-worker(claude/codex/omp) 상호 비판 리뷰 합의 반영.

### Added
- `scripts/yt_fetch.sh media <URL> <DIR>` — 영상 1회 다운로드 + 검증된 캐시 재사용 (`.part`/오디오 없는 잔존물 거부, 임시 디렉토리 경유 원자적 배치), `{status, path, cached}` JSON 출력.
- `scripts/yt_fetch.sh transcribe <FILE|URL> <DIR>` — 자막 체크 없이 바로 Whisper 전사 (Groq → OpenAI fallback) + 기존 산출물 재사용 가드 (`whisper_model:"cached"`).
- `scripts/yt_fetch.sh captions ... --captions-only` — 자막 부재 시 Whisper 로 넘어가지 않는 교차 검증 전용 모드 (자막 부재 = `status:"ok"` + 빈 `caption_files`). preview 는 플래그 없는 기존 동작 그대로.
- AV-first 통합 bats 시나리오 (다운로드 1회 + whisper/captions 산출물 분리 검증).

### Changed
- **youtube-adapter** — 분석 우선순위 반전: frames(시각) + Whisper(오디오) 를 `intent.focus` 무관 **항상** 수행, 자막은 고유명사·숫자·용어 교차 검증용으로 강등 (Whisper 실패 시 자막이 주 전사본으로 승격). 영상 다운로드 2회 → 1회 (`media` 캐시 공유). 산출물은 `$cache_dir` 아래 `media/`·`frames/`·`whisper/`·`captions/` 로 분리 (whisper.vtt 자막 오인 차단). media 실패 시 재다운로드 금지(captions-only fallback). transcript 는 파일 직접 쓰기 대신 `artifacts.transcript_md` 반환. findings `source_type` 에 `youtube-whisper` 구분 추가.
- `commands/research.md` — youtube-adapter timeout 5분 → 20분 (긴 영상 AV-first 대응).
- `skills/research-engine/SKILL.md` — preview(자막 우선, 무변경) vs 본 분석(AV-first) 구분 명시.

### Fixed
- `captions` 가 디렉토리 내 `whisper.vtt` 를 자막으로 오인 카운트하던 잠재 버그 (재실행 시 발생) — vtt 탐지에서 `whisper.vtt` 제외.
```

- [ ] **Step 2: plugin.json 버전 bump**

`.claude-plugin/plugin.json` 에서 `"version": "0.16.0"` → `"version": "0.17.0"`.

- [ ] **Step 3: 검증**

Run: `jq -r .version .claude-plugin/plugin.json`
Expected: `0.17.0`

- [ ] **Step 4: 커밋**

```bash
git add CHANGELOG.md .claude-plugin/plugin.json
git commit -m "chore(release): 0.17.0 — youtube AV-first analysis"
```

---

### Task 9: 최종 회귀 + 머지 준비

- [ ] **Step 1: yt_fetch 전체 테스트**

Run: `bats tests/bats/test_yt_fetch.bats`
Expected: 18 tests, 0 failures

- [ ] **Step 2: bats 스위트 전체 회귀 (yt_fetch 외 스크립트 영향 없음 확인)**

Run: `bats tests/bats/`
Expected: 전부 통과 (이 변경은 `yt_fetch.sh` 외 스크립트를 건드리지 않으므로 실패 시 기존 환경 문제와 구분할 것 — main 에서도 실패하는 테스트인지 `git stash` 후 대조)

- [ ] **Step 3 (권장): 긴 영상 1건 실측**

30분+ 실제 YouTube 영상으로 AV-first 전체 경로 실행 — media 다운로드 + transcribe + frames + captions-only 가 20분 timeout 안에 완료되는지, 산출물 디렉토리 구조가 spec §3.0 과 일치하는지 확인. (API 키 필요 — 환경에 없으면 skip 하고 보고에 명시.)

- [ ] **Step 4: 사용자 확인 후 push + main 머지**

push 는 공유 원격 변경이므로 사용자에게 확인 후:

```bash
gh auth status   # gprecious 활성 확인
git push -u origin feat/youtube-av-first
# 머지 방식(직접 머지 vs PR)은 사용자 선택
```

- [ ] **Step 5: 배포 확인**

main 머지 후 이 머신에서 `claude` 의 marketplace update 로 research-engine 0.17.0 이 받아지는지 확인.
