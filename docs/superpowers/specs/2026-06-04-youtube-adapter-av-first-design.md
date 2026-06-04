# youtube-adapter — 영상·소리 분석 우선 (AV-first) Design Spec

**Status:** Approved (brainstorming phase)
**Date:** 2026-06-04
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
   1시간 ≈ $0.1 수준으로 비용 부담 작음).
4. **preview 단계(`commands/research.md`)는 현행 유지** — 자막 우선의 가벼운
   미리보기. 본 분석(youtube-adapter)만 AV-first 로 변경.

### 1.2 Non-goals

- preview 파이프라인의 AV-first 전환 (시작 지연 수 분 → 명시적으로 제외).
- `captions` 서브커맨드의 기존 기본 동작 변경 (preview 호환성 유지).
- 프레임 샘플링 정책(`auto_fps`, `MAX_FRAMES`) 변경.

## 2. 변경 대상

| 파일 | 변경 |
|---|---|
| `scripts/yt_fetch.sh` | `media`, `transcribe` 서브커맨드 신설 + `captions --captions-only` 플래그 |
| `agents/youtube-adapter.md` | 플로우 재배열 (AV-first), frames 조건 삭제 |
| `skills/research-engine/SKILL.md` | YouTube 분석 설명을 새 플로우에 맞춰 갱신 |
| `tests/bats/test_yt_fetch.bats` | 신규 서브커맨드/플래그 테스트 + 기존 10개 회귀 |
| `CHANGELOG.md` | 0.17.0 항목 |
| `.claude-plugin/plugin.json` | `0.16.0` → `0.17.0` (동작 변경 = minor) |

marketplace(`gprecious-marketplace`) 는 URL source 라 **변경 불필요**.

## 3. `yt_fetch.sh` 설계

### 3.1 `media <URL> <DIR>` (신설)

기존 `download_video` 함수 노출. 영상을 `<DIR>` 에 **1회만** 다운로드하고 경로를
JSON 으로 출력.

- 이미 video 파일이 존재하면 재다운로드 없이 그 경로를 반환 (캐시 재사용).
- `fresh` 처리: 어댑터가 `fresh=true` 일 때 기존 패턴대로 cache dir 을 비우고 호출
  (스크립트 자체에는 fresh 개념 없음 — 파일 부재 = 다운로드).
- 출력: `{"status":"ok","path":"<abs path>"}` / 실패 시 비-0 exit + stderr.

### 3.2 `transcribe <FILE|URL> <DIR>` (신설)

자막 체크 없이 **바로 Whisper** 전사. 기존 `whisper_fallback` 함수 노출.

- 로컬 FILE 을 받으면 재다운로드 없음 (ffmpeg 오디오 추출 → Groq → OpenAI fallback).
- 출력 스키마는 기존 captions 의 whisper 경로와 동일:
  `{status, transcript_source:"whisper", whisper_model, transcript_vtt, transcript_json, failures}`.
- 키 미설정/양쪽 실패 시 기존과 동일하게 `status:"partial"`, `transcript_source:"none"`.

### 3.3 `captions <URL> <DIR> [--captions-only]` (플래그 추가)

- `--captions-only`: 자막 부재 시 Whisper 로 넘어가지 않고
  `{status:"partial", transcript_source:"none", caption_files:[]}` 로 종료.
- **플래그 없으면 현행 동작 그대로** (자막 부재 → whisper fallback) → preview 무변경 호환.

## 4. `agents/youtube-adapter.md` 새 플로우

```
1. metadata                                  (변경 없음)
2. media 다운로드 1회 → 로컬 경로 확보       (yt_fetch.sh media)
3. 항상 수행 (조건 제거):
   ├─ frames    (로컬 파일에서)  → 시각 watch pass (JPEG Read)
   └─ transcribe (로컬 파일에서) → Whisper 주 전사본
4. captions --captions-only → 자막 있으면 Whisper 전사와 교차 검증
   (고유명사·숫자·용어 교정, 불일치 구간 기록)
5. transcript.md = Whisper 주 전사본에 자막 교정 반영, 헤더에 전사 출처 명시
6. findings source_type:
   - 오디오 기반   → "youtube-whisper"
   - 화면 기반     → "youtube-frame"
   - 자막 인용     → "youtube-captions"
   교차 검증 불일치는 해당 finding 에 신뢰도 메모.
```

기존 step 4 의 "intent.focus 에 visual/demo/UI… 신호가 있을 때만 frames" 조건은 **삭제**.

## 5. Fallback 체인 (실패 모드)

| 상황 | 동작 |
|---|---|
| Whisper 실패 (키 없음 / 양쪽 API 실패) | 자막이 주 전사본으로 승격 (= 현행 동작). frames 는 그래도 항상 수행. `partial` + `failures:[{step:"whisper"}]` |
| media 다운로드 실패 | frames·Whisper 불가. captions 는 `--skip-download` 라 독립 → 자막 기반 분석으로 `partial`, 자막도 없으면 `failed` |
| frames 실패 | Whisper transcript 로 계속, `partial` + `failures:[{step:"frames"}]` |
| yt-dlp 미설치 | `failed` (변경 없음) |

## 6. 테스트 계획 (bats)

- `transcribe`: mock curl 로 Whisper 성공 경로 (vtt/json 생성) + 실패 경로 (`partial`).
- `media`: mock yt-dlp 로 다운로드 + 두 번째 호출 시 캐시 재사용 (yt-dlp 미호출) 검증.
- `captions --captions-only`: 자막 부재 시 Whisper 를 **호출하지 않음** 검증.
- 기존 10개 테스트 회귀 통과 (플래그 없는 `captions` 동작 불변 확인).

## 7. 배포

1. `feat/youtube-av-first` 브랜치에서 TDD 구현 (RED → GREEN).
2. bats 전체 통과 확인.
3. `plugin.json` 0.17.0 + `CHANGELOG.md` 갱신.
4. `gprecious` 계정 확인 후 push → main 머지.
5. 이 머신에서 `marketplace update` 로 0.17.0 반영 확인.
