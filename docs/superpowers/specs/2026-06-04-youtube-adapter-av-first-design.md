# youtube-adapter — 영상·소리 분석 우선 (AV-first) Design Spec

**Status:** Approved (brainstorming phase) — rev.2 (3-worker 상호 비판 리뷰 반영: claude/codex/omp)
**Date:** 2026-06-04 (rev.2: 2026-06-05)
**Owner:** harry@qplace.kr

## 1. 목적 (Purpose)

현재 youtube-adapter 는 **자막(captions) 텍스트가 주 분석 소스**다. 자막이 있는 영상은
프레임(시각) 분석이 `intent.focus` 에 visual 신호가 있을 때만 조건부로 수행되고,
오디오(Whisper) 전사는 자막 부재 시의 fallback 일 뿐이다. 그 결과:

- 자막이 있는 평범한 영상은 **화면을 한 장도 보지 않고** findings 를 생성한다.
- 자동 생성 자막의 오류(고유명사·숫자·용어)가 그대로 findings 에 들어간다.

이 변경은 분석 우선순위를 뒤집는다: **프레임(영상) + Whisper(오디오) 분석을 모든
영상에서 기본으로 항상 수행**하고, 자막은 **교차 검증용 보조 소스**로 강등한다.

### 1.1 확정 요구사항

1. frames + Whisper 분석을 자막 유무와 무관하게 **항상** 수행.
2. 자막은 **교차 검증용** — Whisper 전사와 대조해 고유명사/숫자/용어를 교정하고,
   불일치 구간은 findings 신뢰도에 반영. Whisper 실패 시 자막이 주 전사본으로 승격.
3. **길이 임계치 없음** — 1시간+ 영상도 동일하게 처리 (Groq whisper-large-v3 기준
   1시간 ≈ $0.1 수준으로 비용 부담 작음). 단 이에 따라 어댑터 timeout 계약을
   상향한다 (§6.5).
4. **preview 단계(`commands/research.md` Stage 2 / SKILL.md step 3)는 현행 유지** —
   자막 우선의 가벼운 미리보기 + visual focus 시 frames 미리보기 안내 포함.
   본 분석(youtube-adapter)만 AV-first 로 변경.

### 1.2 Non-goals

- preview 파이프라인의 AV-first 전환 (시작 지연 수 분 → 명시적으로 제외).
- `captions` 서브커맨드의 플래그 없는 기본 동작 변경 (preview 호환성 유지).
  예외 1건: `whisper.vtt` 를 자막으로 오인 카운트하던 잠재 버그의 수정(§3.3)은
  기본 동작에도 적용 — 이것은 "현행 유지" 가 아니라 "현행 버그 수정" 이다.
- 프레임 샘플링 정책(`auto_fps`, `MAX_FRAMES`) 변경.

## 2. 변경 대상

| 파일 | 변경 |
|---|---|
| `scripts/yt_fetch.sh` | `media`, `transcribe` 서브커맨드 신설 + `captions --captions-only` 플래그 + whisper.vtt 오인 방지 필터 + whisper 결과 재사용 가드 |
| `agents/youtube-adapter.md` | 플로우 재배열 (AV-first), frames 조건 삭제, 산출물 디렉토리 분리, transcript 는 `artifacts.transcript_md` 반환 |
| `skills/research-engine/SKILL.md` | preview 안내는 유지하고 본 분석 AV-first 설명 추가 |
| `commands/research.md` | youtube-adapter timeout 상향 (5분 → 20분, §6.5) |
| `README.md` | Requirements 에 ffmpeg/ffprobe 추가 (AV-first 필수 의존성) |
| `tests/bats/test_yt_fetch.bats` | 신규 서브커맨드/플래그/오염 방지/통합 시나리오 테스트 + 기존 10개 회귀 |
| `CHANGELOG.md` | 0.17.0 항목 |
| `.claude-plugin/plugin.json` | `0.16.0` → `0.17.0` (동작 변경 = minor) |

marketplace(`gprecious-marketplace`) 는 URL source 라 **변경 불필요**.

## 3. `yt_fetch.sh` 설계

### 3.0 산출물 디렉토리 분리 (rev.2 — 3인 만장일치 critical 수정)

`captions` 서브커맨드는 `find "$dir" -name '*.vtt'` 카운트로 자막 유무를 판정하므로,
`transcribe` 가 같은 디렉토리에 만든 `whisper.vtt` 가 **자막으로 오인**된다
(교차 검증이 Whisper 전사본을 자기 자신과 대조하게 됨). 이를 원천 차단하기 위해
어댑터는 산출물별 전용 하위 디렉토리를 쓴다:

```
$cache_dir/              # = research/<slug>/cache/yt-dlp-<id>/ (이 어댑터 소유)
├── media/               # media 서브커맨드 (영상 1회 다운로드)
├── frames/              # frames 서브커맨드
├── whisper/             # transcribe 서브커맨드 (whisper.vtt/json)
└── captions/            # captions --captions-only (자막 vtt)
```

추가 방어선으로 `captions` 의 vtt 카운트/수집 find 두 곳에 `! -name 'whisper.vtt'`
필터를 넣는다 (디렉토리 분리가 깨져도 오인하지 않도록; 플래그 없는 preview 경로의
잠재 버그도 함께 수정됨).

### 3.1 `media <URL> <DIR>` (신설)

기존 `download_video` 함수 기반. 영상을 `<DIR>` 에 **1회만** 다운로드하고 경로를
JSON 으로 출력.

- **캐시 판정**: `<DIR>` 에 video 파일이 있으면 재사용하되, (a) `*.part`(중단된
  다운로드) 는 후보에서 제외하고 (b) `ffprobe` 로 **오디오 스트림 존재**를 검증한다
  (병합 전 video-only 잔존 파일이 캐시로 고착되는 것 방지). 검증 실패 시 해당
  파일을 지우고 재다운로드.
- **다운로드 원자성**: `<DIR>/.dl-tmp` 임시 디렉토리에 받고 완료 후 `<DIR>` 로
  move — 중단된 다운로드가 캐시 후보로 보이지 않게 한다.
- `fresh` 처리: 어댑터가 `fresh=true` 일 때 **자기 소유 디렉토리
  (`$cache_dir` = `research/<slug>/cache/yt-dlp-<id>/`) 의 내용만** 비우고 호출한다.
  공유 cache root (`<report_dir>/cache/` — preview/memory/타 어댑터 산출물 위치)
  를 지우는 지시는 금지 (스크립트 자체에는 fresh 개념 없음 — 파일 부재 = 다운로드).
- 출력: `{"status":"ok","path":"<abs path>","cached":true|false}` / 실패 시 비-0
  exit + stderr (실패 분기는 `if ! media_path=$(...)` 로 명시 처리해 진단 메시지 보장).
- 의존성: `ffprobe` 필요 (frames 와 동일 — AV-first 에서 ffmpeg/ffprobe 는 공통 필수).

### 3.2 `transcribe <FILE|URL> <DIR>` (신설)

자막 체크 없이 **바로 Whisper** 전사. 기존 `whisper_fallback` 함수 노출.

- 로컬 FILE 을 받으면 재다운로드 없음 (ffmpeg 오디오 추출 → Groq → OpenAI fallback).
- **재사용 가드 (rev.2)**: `<DIR>/whisper.vtt` + `whisper.json` 이 이미 있으면 API
  호출 없이 그대로 반환 (`whisper_model:"cached"`) — 어댑터 재실행 시 Whisper 비용
  중복 방지. fresh 는 어댑터가 디렉토리를 비우는 것으로 처리.
- 출력 스키마는 기존 captions 의 whisper 경로와 동일:
  `{status, transcript_source:"whisper", whisper_model, transcript_vtt, transcript_json, failures}`.
- 키 미설정/양쪽 실패 시 기존과 동일하게 `status:"partial"`, `transcript_source:"none"`.

### 3.3 `captions <URL> <DIR> [--captions-only]` (플래그 추가)

- `--captions-only`: 자막 부재 시 Whisper 로 넘어가지 않고
  `{status:"ok", transcript_source:"none", caption_files:[], failures:[]}` 로 종료.
  - **status 의미 (rev.2 결정)**: 교차 검증 모드에서 자막 부재는 실패가 아니라
    정상 결과이므로 `"ok"` + 빈 `caption_files` 로 표현한다 (`"partial"` + 빈
    `failures` 조합은 "일부 실패" 관례와 충돌). 호출자는 `caption_files | length`
    로 자막 유무를 판단한다.
- vtt 카운트/수집에서 `whisper.vtt` 제외 (§3.0 — 플래그 유무 무관 공통 적용).
- **그 외 플래그 없는 동작은 현행 유지** (자막 부재 → whisper fallback) → preview
  경로(`commands/research.md` Stage 2) 무변경 호환.

## 4. `agents/youtube-adapter.md` — 새 플로우

```
1. metadata                                   (변경 없음)
2. media 다운로드 1회 → $cache_dir/media → 로컬 경로 확보
   └─ 실패 시: steps 3–5 전부 skip, captions --captions-only 로 자막만 시도
      (재다운로드/Whisper 재시도 금지), 자막 있으면 자막-주전사 모드로 진행
3. 항상 수행 (조건 제거):
   ├─ frames     → $cache_dir/frames   (로컬 파일에서) → 시각 watch pass
   └─ transcribe → $cache_dir/whisper  (로컬 파일에서) → Whisper 주 전사본
4. captions --captions-only → $cache_dir/captions
   ├─ 캐시 가드: captions/ 에 자막 vtt 가 이미 있고 fresh 아니면 호출 생략
   ├─ 자막 있음 + Whisper 성공 → 교차 검증 (고유명사·숫자·용어 교정, 불일치 기록)
   ├─ 자막 있음 + Whisper 실패 → 자막을 주 전사본으로 승격 (기존 동작)
   └─ 자막 없음 → 교차 검증 skip
5. transcript: 주 전사본(+자막 교정 반영)을 **`artifacts.transcript_md` 로 반환**
   (직접 파일 쓰기 금지 — dispatch 입력에 report_dir 가 없고, Stage 5 가
   artifacts.transcript_md 를 받아 <report_dir>/transcript.md 로 쓰는 것이 계약).
   markdown 첫 줄에 전사 출처 (whisper:<model> | captions:<lang>) + 교차 검증
   적용 여부 명시.
6. findings source_type: 오디오 기반 "youtube-whisper" / 화면 기반 "youtube-frame"
   / 자막 인용 "youtube-captions" — 교차 검증 불일치는 신뢰도 메모
```

기존 step 4 의 "intent.focus 에 visual 신호가 있을 때만 frames" 조건은 **삭제**.

## 5. Fallback 체인 (실패 모드)

| 상황 | 동작 |
|---|---|
| Whisper 실패 (키 없음 / 양쪽 API 실패) | 자막이 주 전사본으로 승격 (= 현행 동작). frames 는 그래도 항상 수행. `partial` + `failures:[{step:"whisper"}]` |
| media 다운로드 실패 | frames·Whisper 불가 (**재시도 금지** — no-flag captions 경유 Whisper 재진입 금지). `captions --captions-only` 로 자막만 시도 → 자막 기반 분석으로 `partial`, 자막도 없으면 `failed` |
| frames 실패 | Whisper transcript 로 계속, `partial` + `failures:[{step:"frames"}]` |
| Whisper·자막 모두 부재 | frames + metadata 만으로 `partial`, failures 양쪽 기록 |
| ffmpeg/ffprobe 미설치 | frames·media 검증·오디오 추출 불가 → 사실상 자막-주전사 모드로 강등, `partial` + `failures:[{step:"ffmpeg_missing"}]` (환경 문제로 명시) |
| yt-dlp 미설치 | `failed` (변경 없음) |

## 6. 테스트 계획 (bats)

- `media`: mock yt-dlp + **실제 AV fixture**(ffmpeg 생성, 오디오 포함) 로 다운로드
  → 두 번째 호출 시 캐시 재사용 (yt-dlp 미호출, ffprobe 검증 통과). `.part` /
  오디오 없는 파일은 캐시로 인정하지 않음.
- `transcribe`: mock curl 로 Whisper 성공 경로 (vtt/json 생성) + 키 부재 실패 경로
  (`partial`) + 재사용 가드 (두 번째 호출 시 curl 미호출).
- `captions --captions-only`: 자막 부재 시 Whisper 를 **호출하지 않고** `ok` +
  빈 caption_files. 디렉토리에 `whisper.vtt` 가 미리 있어도 자막으로 오인하지 않음
  (오염 regression).
- **AV-first 통합 시나리오**: media → frames(로컬 파일) → transcribe → captions-only
  를 실제 어댑터 순서·디렉토리 구조로 실행 — yt-dlp 다운로드 횟수 1회,
  whisper.vtt 와 captions 결과 미혼합, frames 가 URL 이 아닌 로컬 경로를 받는지 검증.
- 기존 10개 테스트 회귀 통과 (플래그 없는 `captions` 동작 불변 확인).

### 6.5 어댑터 timeout (rev.2)

`commands/research.md` 의 "Timeout per adapter: 5 minutes" 는 자막-우선(수십 초)
기준 계약이다. AV-first 는 1시간+ 영상에서 다운로드(수백 MB) + 오디오 추출 +
Whisper 업로드/전사 + 54프레임 Read 를 포함하므로 5분을 초과할 수 있다.
**youtube-adapter 에 한해 20분**으로 상향한다 (다른 어댑터는 5분 유지).

## 7. 배포

1. `feat/youtube-av-first` 브랜치에서 TDD 구현 (RED → GREEN).
2. bats 전체 통과 확인.
3. (권장) 긴 영상 1건 실측 — 30분+ 영상으로 AV-first 전체 경로와 소요 시간 확인.
4. `plugin.json` 0.17.0 + `CHANGELOG.md` 갱신.
5. `gprecious` 계정 확인 후 push → main 머지.
6. 이 머신에서 `marketplace update` 로 0.17.0 반영 확인.

---

## 부록: rev.2 변경 근거

2026-06-05, herdr 3-worker (claude Opus 4.8 / codex GPT-5.5 / omp GPT-5.5) 상호
비판 리뷰 2라운드의 만장일치 합의 반영. 상세는 `.review/round{1,2}-*.md` (로컬).

- critical: whisper.vtt ↔ captions 오염 (§3.0)
- major: media 실패 fallback 재다운로드 금지 (§4·§5), transcript 계약
  (`artifacts.transcript_md`, §4), fresh 삭제 범위 (§3.1), 깨진 media 캐시 고착
  방지 (§3.1), timeout 상향 (§6.5), 통합 테스트 (§6)
- minor: `cached` 필드 명세화 (§3.1), captions-only status 의미 (§3.3), preview
  frames 안내 유지 (§1.1.4), ffmpeg failure mode (§5), captions 캐시 가드 (§4),
  whisper 재사용 가드 (§3.2)
