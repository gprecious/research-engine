# youtube-adapter AV-first Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** youtube-adapter 의 분석 우선순위를 자막 우선 → 영상(frames)+오디오(Whisper) 우선으로 전환하고, 영상 다운로드를 1회로 통합한다.

**Architecture:** `scripts/yt_fetch.sh` 에 `media`(1회 다운로드+캐시), `transcribe`(자막 체크 없이 바로 Whisper) 서브커맨드와 `captions --captions-only` 플래그를 추가한다. 기존 `download_video`/`whisper_fallback` 내부 함수를 그대로 노출하는 방식이라 신규 로직은 최소다. 그 위에서 `agents/youtube-adapter.md` 플로우를 재배열한다 (frames+Whisper 항상 수행, 자막은 교차 검증). preview 경로(`commands/research.md`)는 무변경 — `captions` 의 플래그 없는 기본 동작이 그대로이기 때문.

**Tech Stack:** bash (yt-dlp/ffmpeg/jq/curl 래퍼), bats (스크립트 테스트), Claude Code agent 정의 (markdown).

**Spec:** `docs/superpowers/specs/2026-06-04-youtube-adapter-av-first-design.md`

**Repo/Branch:** `gprecious/research-engine`, 브랜치 `feat/youtube-av-first` (이미 생성됨, spec 커밋 포함)

**테스트 실행법:** repo 루트에서 `bats tests/bats/test_yt_fetch.bats` (bats, ffmpeg, jq 필요 — 기존 테스트 10개가 이미 사용 중)

---

### Task 1: `yt_fetch.sh media` 서브커맨드

**Files:**
- Modify: `scripts/yt_fetch.sh` (case 블록에 `media)` 분기 추가 — `captions)` 분기 앞)
- Test: `tests/bats/test_yt_fetch.bats` (파일 끝에 추가)

- [ ] **Step 1: 실패하는 테스트 작성**

`tests/bats/test_yt_fetch.bats` 끝에 추가:

```bash
@test "media subcommand downloads once and reuses cached file on second call" {
  printf 'fake-video-bytes' > "$TMPDIR_TEST/src.mp4"

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
```

- [ ] **Step 2: 실패 확인**

Run: `bats tests/bats/test_yt_fetch.bats -f "media subcommand"`
Expected: FAIL — `yt_fetch: unknown subcommand: media`

- [ ] **Step 3: 최소 구현**

`scripts/yt_fetch.sh` 의 `case "${1:-}" in` 블록에서 `captions)` 분기 **앞**에 추가:

```bash
  media)
    [[ $# -eq 3 ]] || die "media needs <URL> <DIR>"
    url="$2"; dir="$3"
    mkdir -p "$dir"
    existing="$(find "$dir" -maxdepth 1 -type f \( -name 'video.*' -o -name '*.mp4' -o -name '*.mkv' -o -name '*.webm' \) | head -n1)"
    if [[ -n "$existing" ]]; then
      jq -n --arg path "$(abs_path "$existing")" '{status:"ok", path:$path, cached:true}'
      exit 0
    fi
    media_path="$(download_video "$url" "$dir")"
    [[ -n "$media_path" && -f "$media_path" ]] || die "media download failed: $url"
    jq -n --arg path "$(abs_path "$media_path")" '{status:"ok", path:$path, cached:false}'
    ;;
```

(`download_video`, `abs_path`, `die` 는 모두 기존 함수 — 새 함수 정의 불필요. `download_video` 는 `-o "$dir/video.%(ext)s"` 로 `$dir` 바로 아래에 다운로드하고 결과 파일 경로를 출력한다.)

- [ ] **Step 4: 통과 확인**

Run: `bats tests/bats/test_yt_fetch.bats -f "media subcommand"`
Expected: 1 test, 0 failures

- [ ] **Step 5: 커밋**

```bash
git add scripts/yt_fetch.sh tests/bats/test_yt_fetch.bats
git commit -m "feat(yt_fetch): add media subcommand — single download with cache reuse"
```

---

### Task 2: `yt_fetch.sh transcribe` 서브커맨드

**Files:**
- Modify: `scripts/yt_fetch.sh` (case 블록에 `transcribe)` 분기 추가 — `media)` 분기 뒤)
- Test: `tests/bats/test_yt_fetch.bats` (파일 끝에 추가)

- [ ] **Step 1: 실패하는 테스트 2개 작성**

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
```

- [ ] **Step 2: 실패 확인**

Run: `bats tests/bats/test_yt_fetch.bats -f "transcribe subcommand"`
Expected: 2 FAIL — `yt_fetch: unknown subcommand: transcribe`

- [ ] **Step 3: 최소 구현**

`scripts/yt_fetch.sh` 의 `media)` 분기 뒤에 추가:

```bash
  transcribe)
    [[ $# -eq 3 ]] || die "transcribe needs <FILE|URL> <DIR>"
    whisper_fallback "$2" "$3"
    ;;
```

(`whisper_fallback` 이 키 로딩 → `extract_audio`(로컬 파일이면 재다운로드 없음) → Groq → OpenAI fallback → JSON 출력까지 전부 처리한다.)

- [ ] **Step 4: 통과 확인**

Run: `bats tests/bats/test_yt_fetch.bats -f "transcribe subcommand"`
Expected: 2 tests, 0 failures

- [ ] **Step 5: 커밋**

```bash
git add scripts/yt_fetch.sh tests/bats/test_yt_fetch.bats
git commit -m "feat(yt_fetch): add transcribe subcommand — direct Whisper, no caption check"
```

---

### Task 3: `captions --captions-only` 플래그 + 헤더/help 갱신

**Files:**
- Modify: `scripts/yt_fetch.sh` (`captions)` 분기 인자 파싱 + else 분기, 파일 상단 주석, help 의 sed 범위)
- Test: `tests/bats/test_yt_fetch.bats` (파일 끝에 추가)

- [ ] **Step 1: 실패하는 테스트 작성**

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
  echo "$output" | jq -e '.status == "partial" and .transcript_source == "none" and (.caption_files | length == 0)' >/dev/null
  [ ! -f "$TMPDIR_TEST/curl-args.txt" ]
}
```

- [ ] **Step 2: 실패 확인**

Run: `bats tests/bats/test_yt_fetch.bats -f "captions-only"`
Expected: FAIL — 현재 `captions` 는 인자 3개를 요구하므로 `captions needs <URL> <DIR>` 에러

- [ ] **Step 3: 구현**

`scripts/yt_fetch.sh` 의 `captions)` 분기 첫 두 줄을 교체.

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

같은 분기의 마지막 else (whisper fallback 진입부) 교체.

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
        jq -n '{status:"partial", transcript_source:"none", caption_files:[], failures:[]}'
      else
        whisper_fallback "$url" "$dir"
      fi
    fi
```

- [ ] **Step 4: 파일 상단 주석 + help 범위 갱신**

파일 상단 주석 블록(2~10행)을 다음으로 교체:

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
```

help 분기의 sed 범위를 새 주석 끝 행에 맞춰 갱신 (기존 `sed -n '2,10p' "$0"` → `sed -n '2,13p' "$0"`):

```bash
  ""|-h|--help)
    sed -n '2,13p' "$0"
    exit 1
    ;;
```

- [ ] **Step 5: 신규 테스트 + 전체 회귀 통과 확인**

Run: `bats tests/bats/test_yt_fetch.bats`
Expected: 14 tests, 0 failures (기존 10 + media 1 + transcribe 2 + captions-only 1). 특히 기존 `captions subcommand reports partial...` / `captions falls back to OpenAI whisper-1...` 2개가 그대로 통과해야 함 (플래그 없는 기본 동작 불변 = preview 호환).

- [ ] **Step 6: 커밋**

```bash
git add scripts/yt_fetch.sh tests/bats/test_yt_fetch.bats
git commit -m "feat(yt_fetch): add --captions-only flag for cross-check-only caption fetch"
```

---

### Task 4: `agents/youtube-adapter.md` AV-first 플로우 재작성

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
- `cache_dir`: path for caching raw downloads (`research/<slug>/cache/yt-dlp-<id>/`)
- `intent`: object with `purpose`, `focus`, `audience_level`
- `slug`: session slug
- `fresh`: bool — if true, bypass cache

## Steps

1. **Metadata** — run `scripts/yt_fetch.sh metadata "$url"` and parse. `selected_caption_lang == ""` only means the cross-check source is absent; the primary AV analysis below proceeds regardless.

2. **Media download (once)** — if `fresh`, delete the contents of `$cache_dir` first. Run `scripts/yt_fetch.sh media "$url" "$cache_dir/media"` and parse `.path` as `$media_path`. This single download is reused by both the frame pass and the Whisper pass.
   - If the download fails: skip steps 3–4, run `scripts/yt_fetch.sh captions "$url" "$cache_dir"` (no flag — the script may still attempt Whisper from the URL) and treat the result as the primary transcript; record `failures: [{"step":"media", ...}]`.

3. **Visual watch pass (always)** — run `scripts/yt_fetch.sh frames "$media_path" "$cache_dir/frames"`. Read `frames.json`, then use the Read tool on the listed JPEG paths. Claude Code and Codex can both inspect local JPEG files via Read/image-capable file reading, so this design is surface-independent: the script only passes file paths and timecodes, and the active agent does the visual interpretation. Extract screen-only evidence such as UI labels, code snippets visible on screen, slide titles, diagram structure, product state, before/after visuals, and demo transitions. Keep frame findings tied to `t_label`.

4. **Whisper transcript (always)** — run `scripts/yt_fetch.sh transcribe "$media_path" "$cache_dir"`.
   - `transcript_source: "whisper"`: use `whisper.vtt` / `whisper.json` as the **primary transcript**; record the provider/model from the `whisper_model` field (`groq:whisper-large-v3`, or `openai:whisper-1` when Groq was unavailable and OpenAI was the fallback).
   - `status: "partial"` (no keys configured / all providers failed): the primary transcript falls to captions in step 5; record the failure entry. Do not mark the whole adapter failed solely because Whisper is absent.

5. **Captions cross-check** — run `scripts/yt_fetch.sh captions "$url" "$cache_dir" --captions-only`.
   - Captions present + Whisper succeeded: compare the caption text against the Whisper transcript. Prefer caption spellings for proper nouns, product/library names, numbers, and technical terms (captions are often author-corrected); keep Whisper wording for everything else. Note spans where the two disagree materially — findings built on such spans must mention the discrepancy.
   - Captions present + Whisper failed: promote captions to the primary transcript (legacy behavior).
   - Captions absent: skip the cross-check. If Whisper also failed, continue with frames and metadata only and set `status: "partial"`.

6. **Transcript** — convert the primary transcript VTT to plain text paragraphs grouped by chapter (or by 2-minute windows if no chapters). Write to `{{report_dir}}/transcript.md` with one paragraph per chapter, prefixed by `### {{chapter_title}} ({{start}}–{{end}})`. Start the file with a one-line header naming the transcript source (`whisper:<model>` or `captions:<lang>`) and whether the caption cross-check was applied.

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
- Media download failed → frames and Whisper are impossible. Fall back to caption-primary mode: `status: "partial"` if captions yield a transcript, `"failed"` if captions are also absent. Record `failures: [{"step":"media", ...}]`.
- Frame extraction failed → continue with the Whisper transcript, `status: "partial"`, record `failures: [{"step":"frames", ...}]`.
- Both Whisper and captions absent → continue with frames and metadata only, `status: "partial"`, record both failure entries.
- yt-dlp missing → `status: "failed"`, `failures: [{"step":"yt_dlp_missing", "error":"..."}]`.
- Partial caption download → cross-check is limited to the downloaded spans; not a failure by itself.
````

- [ ] **Step 2: 일관성 검증**

Run: `grep -c "evolvable" agents/youtube-adapter.md`
Expected: `4` (findings-guidance 열림/닫힘 + intent-tailoring 열림/닫힘)

Run: `grep -n "captions-only\|yt_fetch.sh media\|yt_fetch.sh transcribe" agents/youtube-adapter.md`
Expected: media 1회(step 2), transcribe 1회(step 4), --captions-only 1회(step 5) 등장

- [ ] **Step 3: 커밋**

```bash
git add agents/youtube-adapter.md
git commit -m "feat(youtube-adapter): AV-first flow — frames+Whisper always, captions as cross-check"
```

---

### Task 5: `skills/research-engine/SKILL.md` 갱신

**Files:**
- Modify: `skills/research-engine/SKILL.md` (31행 YouTube preview 불릿)

- [ ] **Step 1: YouTube 불릿 교체**

기존 (31행):

```
   - YouTube: verify `yt-dlp`; fetch metadata and transcript with `scripts/yt_fetch.sh`. Captions are preferred; if captions are absent, `captions` attempts Groq Whisper fallback from `GROQ_API_KEY` (env or `~/.config/research-engine/`) and otherwise returns partial status. For visual/demo/tutorial focus or missing transcript, run `scripts/yt_fetch.sh frames <url> <cache>/frames` and Read the JPEG paths in `frames.json`.
```

신규:

```
   - YouTube: verify `yt-dlp`; fetch metadata and transcript with `scripts/yt_fetch.sh`. For the lightweight preview, captions are preferred; if captions are absent, `captions` attempts Groq Whisper fallback from `GROQ_API_KEY` (env or `~/.config/research-engine/`) and otherwise returns partial status. Full analysis (the youtube-adapter, or its direct equivalent on Codex) is AV-first: download media once with `yt_fetch.sh media`, always run `frames` + `transcribe` (Whisper primary transcript), and use `captions --captions-only` only to cross-check proper nouns/numbers/terms against the Whisper transcript.
```

- [ ] **Step 2: 검증**

Run: `grep -n "AV-first" skills/research-engine/SKILL.md`
Expected: 1 hit (31행 근처)

- [ ] **Step 3: 커밋**

```bash
git add skills/research-engine/SKILL.md
git commit -m "docs(skill): document AV-first full analysis vs captions-first preview"
```

---

### Task 6: CHANGELOG + plugin.json 0.17.0

**Files:**
- Modify: `CHANGELOG.md` (`## [Unreleased]` 아래에 0.17.0 섹션 삽입)
- Modify: `.claude-plugin/plugin.json` (`"version": "0.16.0"` → `"0.17.0"`)

- [ ] **Step 1: CHANGELOG 에 0.17.0 섹션 추가**

`## [Unreleased]` 바로 아래에 삽입:

```markdown
## [0.17.0]

YouTube 분석 AV-first 전환 — 영상(frames)+오디오(Whisper)를 모든 영상에서 기본 수행, 자막은 교차 검증용.

### Added
- `scripts/yt_fetch.sh media <URL> <DIR>` — 영상 1회 다운로드 + 캐시 재사용, `{status, path, cached}` JSON 출력.
- `scripts/yt_fetch.sh transcribe <FILE|URL> <DIR>` — 자막 체크 없이 바로 Whisper 전사 (Groq → OpenAI fallback).
- `scripts/yt_fetch.sh captions ... --captions-only` — 자막 부재 시 Whisper 로 넘어가지 않는 교차 검증 전용 모드 (preview 는 플래그 없는 기존 동작 그대로).

### Changed
- **youtube-adapter** — 분석 우선순위 반전: frames(시각) + Whisper(오디오) 를 `intent.focus` 무관 **항상** 수행, 자막은 고유명사·숫자·용어 교차 검증용으로 강등 (Whisper 실패 시 자막이 주 전사본으로 승격). 영상 다운로드 2회 → 1회 (`media` 캐시 공유). findings `source_type` 에 `youtube-whisper` 구분 추가.
- `skills/research-engine/SKILL.md` — preview(자막 우선, 무변경) vs 본 분석(AV-first) 구분 명시.
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

### Task 7: 최종 회귀 + 머지 준비

- [ ] **Step 1: yt_fetch 전체 테스트**

Run: `bats tests/bats/test_yt_fetch.bats`
Expected: 14 tests, 0 failures

- [ ] **Step 2: bats 스위트 전체 회귀 (yt_fetch 외 스크립트 영향 없음 확인)**

Run: `bats tests/bats/`
Expected: 전부 통과 (이 변경은 `yt_fetch.sh` 외 스크립트를 건드리지 않으므로 실패 시 기존 환경 문제와 구분할 것 — main 에서도 실패하는 테스트인지 `git stash` 후 대조)

- [ ] **Step 3: 사용자 확인 후 push + main 머지**

push 는 공유 원격 변경이므로 사용자에게 확인 후:

```bash
gh auth status   # gprecious 활성 확인
git push -u origin feat/youtube-av-first
# 머지 방식(직접 머지 vs PR)은 사용자 선택
```

- [ ] **Step 4: 배포 확인**

main 머지 후 이 머신에서 `claude` 의 marketplace update 로 research-engine 0.17.0 이 받아지는지 확인.
