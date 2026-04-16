# research-engine — Design Spec

**Status:** Approved (brainstorming phase)
**Date:** 2026-04-16
**Owner:** harry@qplace.kr

## 1. 목적 (Purpose)

사용자가 던진 **링크** 또는 **주제**를 깊게 분석해, 출처가 명확하고 구조화된 마크다운 리포트를 생성하는 Claude Code 슬래시 커맨드 기반 리서치 엔진.

### 1.1 주요 Use Case

- **U1.** 유튜브 영상 링크 → 자막 기반 요약 + 타임코드 인용 + 관련 논문/레포/블로그 자동 수집.
- **U2.** arXiv 논문 링크 → 초록/본문 분석 + 인용된 관련 연구 + 구현 레포 찾기.
- **U3.** GitHub 레포 링크 → README/이슈/주요 파일 분석 + 설계 이유 + 관련 논문/블로그.
- **U4.** 일반 블로그 / 문서 링크 → 본문 추출 + 주제 확장 리서치.
- **U5.** 주제 키워드 ("최근 MoE LLM 트렌드") → 유튜브/논문/GitHub/커뮤니티 교차 수집 + 종합.
- **U6.** 기존 리서치 세션에 후속 질문 ("저자 배경 더", "이 레포 대안 찾아줘").

### 1.2 Non-goals

- SNS(X/Twitter, LinkedIn) 분석 — 공식 API 제약으로 범위에서 제외.
- 실시간 스트리밍 / 라이브 영상 — 자막 확정 후만 지원.
- 이미지/동영상 자체의 비주얼 분석 — 자막·텍스트 기반만.
- 유료 페이월 돌파 — 공개 접근 가능한 자료만.

## 2. 인터페이스 (Slash Commands)

### 2.1 `/research <target> [flags]`

**target**: URL(YouTube/arXiv/GitHub/blog/docs), 또는 자연어 주제 문자열.

**flags**:
- `--yes` — Intent Q&A 스킵, 프리뷰 기반으로 엔진이 자동 판단하여 진행.
- `--fresh` — 동일 URL에 대한 캐시를 무시하고 새로 수집.
- `--slug <name>` — 저장 slug를 수동 지정 (기본: 제목에서 자동 생성).

**동작**: 5단계 오케스트레이션 (§4).

### 2.2 `/research-followup [질문] [flags]`

**질문**: 자연어. 비워두면 "다음에 뭐 알고 싶은지?"를 되물음.

**flags**:
- `--slug <name>` — 특정 세션 지정 (기본: 가장 최근 세션).
- `--fresh` — 필요 시 새 자료 수집 강제.

**동작**:
1. `--slug` 없으면 `research/` 디렉토리의 최신 mtime 폴더를 사용.
2. `README.md`, `sources.json`, `session.md`를 컨텍스트로 로드.
3. 질문이 새 자료를 요구하면 타겟 어댑터 subagent 1~2개만 dispatch, 아니면 기존 컨텍스트에서만 답변.
4. 응답을 `session.md`에 append-only로 누적.

## 3. 설계 원칙 (Design Principles)

1. **출처 추적성**: 리포트의 모든 사실성 진술에 소스 번호 `[n]` 표기. `sources.json`과 일대일 매핑.
2. **부분 실패 허용**: 어댑터 하나가 죽어도 나머지는 진행. 리포트 끝에 `## 수집 실패 (Failures)` 섹션으로 기록.
3. **Intent 반영**: 리포트의 톤·깊이·선별 우선순위는 사용자의 Intent 답변에 따라 달라짐.
4. **캐시 우선**: 동일 URL 재실행은 `cache/` 히트 시 재다운로드 생략. `--fresh` 로만 강제 갱신.
5. **병렬 fanout**: 본격 수집 단계는 `superpowers:dispatching-parallel-agents`로 어댑터들을 병렬 실행.
6. **Idempotent**: 같은 입력 + 같은 Intent로 재실행하면 (캐시 덕분에) 비슷한 결과. 비결정성은 LLM 합성 단계에만 존재.

## 4. 오케스트레이션 (5-Stage Pipeline)

### Stage 1 — Classify

입력 분류:
- URL 패턴 매칭으로 소스 타입 감지 (youtube.com/youtu.be, arxiv.org, github.com, huggingface.co, 기타).
- URL이 아니면 → Topic 모드.
- 혼합 입력(URL + 추가 키워드)은 "URL 주도, 키워드는 Intent 힌트"로 해석.

### Stage 2 — Preview

목적: Stage 3의 동적 Intent 질문을 만들기 위한 **얕은** 소스 이해.

- **YouTube**: `yt-dlp --skip-download --write-auto-sub --write-sub --dump-json <url>` 로 제목/설명/챕터/자막 메타 + 자막 앞 5분 추출. 자막 언어 우선순위는 **영상 원어 → 한국어 → 영어 → 그 외**; 선택된 자막 언어는 `sources.json`에 기록.
- **arXiv**: `huggingface-skills:hugging-face-paper-pages` 로 제목+초록+저자.
- **GitHub**: `gh repo view <owner/repo>` + README 첫 섹션.
- **Blog/Docs**: firecrawl scrape (단일 URL, 마크다운 추출).
- **Topic**: WebSearch 상위 3~5건의 제목+스니펫.

프리뷰 결과는 메모리에 보관. `--fresh` 가 아니면 `cache/preview-<hash>.json` 으로 저장해 재사용.

### Stage 3 — Intent Clarification

`--yes`가 아니면:
- 프리뷰를 근거로 **동적 질문** 1~3개 생성. 예:
  - "영상이 A, B, C를 다루는 것 같은데 어느 쪽에 집중할까요?"
  - "학습용 / 의사결정 / 공유용 중 어느 쪽인가요?"
- 사용자 응답을 **Intent 블록**으로 구조화 (`intent.purpose`, `intent.focus`, `intent.audience` 등).

`--yes` 일 때:
- 엔진이 프리뷰만으로 Intent를 추정. 리포트의 Intent 섹션에 "추정(assumed)" 표시.

**실행 모델**: `/research` 슬래시 커맨드는 Intent Q&A 응답을 받을 때까지 블로킹. 사용자는 터미널에서 응답을 타이핑하고, 그 뒤 Stage 4로 진행.

### Stage 4 — Plan & Parallel Dispatch

**Plan**: Intent + 소스 타입을 조합해 어댑터별 작업 계획 생성.
- 예: YouTube 입력 + 학습용 의도 → `youtube-adapter`(메인), `arxiv-adapter`(영상에서 언급된 논문), `github-adapter`(구현 레포), `context7-adapter`(언급된 라이브러리 docs).
- 예: Topic 입력 → 모든 1급 어댑터에 동일 키워드 분배.

**Dispatch**: `superpowers:dispatching-parallel-agents` 로 각 어댑터를 독립 subagent로 실행.
- 각 subagent 프롬프트에 포함: (a) Intent 요약, (b) 어댑터별 작업 지시, (c) 출력 스키마(반드시 구조화된 JSON + 마크다운).
- 타임아웃: 어댑터당 기본 5분, 초과 시 해당 어댑터만 skip하고 실패 기록.

### Stage 5 — Synthesize & Persist

1. 모든 어댑터 결과(성공 + 실패)를 수집.
2. 섹션 템플릿에 따라 마크다운 조립 (§6).
3. `research/YYYY-MM-DD-<slug>/` 폴더에 파일 쓰기.
4. 사용자에게 경로 + 한 줄 요약 반환.

## 5. Source Adapters (어댑터 상세)

### 5.1 1급 어댑터 (tier 1)

| 어댑터 | 주 도구 | 산출물 | 비고 |
|---|---|---|---|
| **youtube-adapter** | `yt-dlp` (CLI) | `transcript.md`, 챕터별 요약, 타임코드 인용 블록 | 한/영 자막 우선, 자동생성 자막 허용 |
| **arxiv-adapter** | `huggingface-skills:hugging-face-paper-pages` + firecrawl | 논문 요약, 인용 관계, 관련 구현 레포 힌트 | arXiv ID 자동 추출 |
| **github-adapter** | `gh` CLI + firecrawl | README 요약, 주요 이슈/PR, 구조 | stars/forks/last-commit 메타 포함 |
| **blog-adapter** | firecrawl (scrape) | 마크다운 본문 + 요약 | 긴 글은 필요시 crawl로 연결 글도 수집 |
| **context7-adapter** | context7 MCP | 언급된 라이브러리의 최신 공식 docs 스니펫 | API/설정/마이그레이션 질의 시 우선 |

### 5.2 2급 어댑터 (tier 2, best-effort)

| 어댑터 | 주 도구 | 산출물 | 비고 |
|---|---|---|---|
| **huggingface-adapter** | `hf` CLI + HF skills | 모델/데이터셋 카드, 라이선스, 리더보드 | 모델명 감지 시 자동 활성 |
| **community-adapter** | firecrawl + WebSearch | HN/Reddit/Lobsters 스레드 요약 | URL 직접 입력 시만 스레드 전체 인용 |

### 5.3 어댑터 공통 계약 (contract)

모든 어댑터는 subagent로서 다음 JSON을 반환:

```json
{
  "adapter": "youtube",
  "status": "ok | partial | failed",
  "sources": [
    {"id": "s1", "type": "youtube-captions", "url": "...", "title": "...", "meta": {...}}
  ],
  "findings": [
    {"text": "...", "source_ids": ["s1"], "timecode": "12:34"}
  ],
  "artifacts": {
    "transcript_md": "...",
    "chapters": [{"title":"...","start":"0:00","end":"2:15","summary":"..."}]
  },
  "failures": [
    {"step": "captions_fetch", "error": "no_auto_captions", "url": "..."}
  ]
}
```

Orchestrator가 `source_ids`를 전역 번호 `[n]`으로 매핑한다.

## 6. 리포트 구조 (Output Schema)

### 6.1 공통 섹션 (모든 리포트)

1. **분석 목적 (Intent)** — 사용자 답변 인용 + 엔진 해석.
2. **요약 (TL;DR)** — 3~5문장.
3. **핵심 포인트** — 불릿 5~10개, 각 포인트 끝에 `[1][2]` 소스 번호.
4. **상세 분석** — 주제별 서브섹션.
5. **인용 / 원문** — 중요 발언·문장 + 출처. 유튜브면 `[mm:ss]` 타임코드 포함.
6. **연관 자료** — 자동 수집한 관련 링크 리스트 (카테고리별: 논문/레포/블로그/docs).
7. **수집 실패 (Failures)** — 실패한 어댑터/단계 요약 (있을 때만).
8. **Sources** — 번호 매긴 전체 소스 리스트 (title, URL, adapter, fetched_at).

### 6.2 유튜브 특화 섹션 (입력이 YouTube일 때 추가)

- **챕터별 요약** — 원본 챕터 또는 자막 기반 자동 구간. 각 챕터에 타임코드 범위와 3~5문장 요약.
- **타임코드 인용** — 영상 내 중요 발언 + 원문 + `[mm:ss]`.
- `transcript.md` 별도 파일로 전체 자막 저장.

### 6.3 언어 규칙

- 본문 한국어 기본.
- 고유명사, 기술 용어, 코드, 직접 인용은 **원문 그대로**.
- 한국어로 풀어 쓸 때 괄호 안에 원어 병기: "전문가 혼합 (Mixture of Experts, MoE)".

## 7. 저장 레이아웃 (Storage)

```
research/
  2026-04-16-<slug>/
    README.md           # 메인 리포트 (§6)
    transcript.md       # 유튜브 자막 원문 (있을 때)
    sources.json        # 구조화 소스 메타데이터 (§5.3 통합판)
    intent.json         # Intent Q&A 원본 기록
    related/
      paper-<arxiv-id>.md
      repo-<owner>-<name>.md
      blog-<hash>.md
    cache/
      preview-<hash>.json      # Stage 2 프리뷰
      adapter-<name>-<hash>.json  # 어댑터 raw 결과
      yt-dlp-<videoId>/        # yt-dlp 원본 파일
    session.md          # followup 누적 로그 (append-only)
```

### 7.1 Slug 규칙

- YouTube: 제목 → slugify → 앞 40자. 예: `attention-is-all-you-need-visualized`.
- arXiv: `arxiv-<id>` 예: `arxiv-2301-12345`.
- GitHub: `gh-<owner>-<repo>`.
- Blog: 도메인 + 경로 → slugify.
- Topic: 키워드 → slugify.
- 충돌 시 `-2`, `-3` 접미사.

### 7.2 Cache 키

- URL의 SHA-1 첫 12자. 어댑터 이름과 조합해 `adapter-<name>-<hash>.json`.

## 8. 구현 배치 (Implementation Layout)

Claude Code 플러그인 형태로 배치:

```
~/.claude/plugins/research-engine/           # or project-local
  plugin.json                                # 플러그인 메타
  commands/
    research.md                              # /research slash command
    research-followup.md                     # /research-followup slash command
  agents/
    youtube-adapter.md
    arxiv-adapter.md
    github-adapter.md
    blog-adapter.md
    context7-adapter.md
    huggingface-adapter.md
    community-adapter.md
    research-synthesizer.md                  # 합성 담당 subagent (옵션)
  scripts/
    yt_fetch.sh                              # yt-dlp 래퍼
    slugify.sh
  lib/
    schema.md                                # 어댑터 공통 계약 (§5.3) 원본
    sections.md                              # 리포트 섹션 템플릿 (§6)
```

## 9. 전제조건 (Prerequisites)

- `yt-dlp` 설치 (YouTube 자막 추출용). 없으면 `/research` 실행 시 설치 방법 안내 후 종료.
- `gh` CLI 인증 (GitHub 어댑터용). 인증 없으면 public API로 fallback.
- firecrawl MCP 활성 (블로그/커뮤니티 어댑터용). 없으면 WebFetch/WebSearch로 fallback.
- context7 MCP 활성 (context7 어댑터용). 없으면 라이브러리 문서는 firecrawl로 fallback.
- huggingface-skills 플러그인 활성 (arXiv/HF 어댑터용).

## 10. 오류 처리 정책

| 실패 유형 | 처리 |
|---|---|
| 어댑터 하나 실패 | 해당 어댑터만 skip, 리포트에 기록. 전체 진행 계속. |
| 모든 어댑터 실패 | 최소 "입력 URL의 원본 메타만 있는" 리포트 생성. 사용자에게 원인 요약 제시. |
| yt-dlp 자막 없음 | `transcript.md` 생략, youtube-adapter는 제목/설명만으로 findings 생성. |
| 프리뷰 단계 실패 | Intent Q&A를 "기본 3개 고정 질문"으로 fallback. |
| 네트워크 오류 | 어댑터당 최대 2회 재시도 후 실패 기록. |
| 캐시 손상 | 감지 시 해당 엔트리만 무효화, 재수집. |

## 11. Open Questions (구현 계획 단계에서 결정)

- 어댑터 subagent의 프롬프트 템플릿 구체 문법 (JSON을 어떻게 강제할지 — free-form JSON vs fenced code-block vs structured output 선택).
- 리포트 분량 가이드라인 (최소/최대 단어 수).
- Topic 모드에서 너무 광범위한 키워드일 때 어댑터별 쿼리를 어떻게 좁힐지 (LLM 기반 쿼리 재작성 단계 추가 여부).
- 어댑터별 타임아웃 기본값 조정 (현 기본 5분 / 어댑터).

## 12. Success Criteria

- **SC1.** YouTube 15분 기술 강연 링크를 주면, 3분 내에 transcript + 챕터별 요약 + 타임코드 인용 + 언급된 논문 1~3개 링크가 있는 리포트가 나온다.
- **SC2.** arXiv 논문 링크를 주면, 초록 요약 + 주요 기여 + 관련 연구 3~5편 + 공식/커뮤니티 구현 레포가 있는 리포트가 나온다.
- **SC3.** "최근 MoE LLM 트렌드" 같은 주제 입력에, 논문 3~5편 + 유튜브 강연 2~3편 + 레포 2~3개를 수집한 종합 리포트가 나온다.
- **SC4.** 동일 URL 재실행(without `--fresh`) 시, 네트워크 I/O 없이 캐시에서 재구성 가능하다.
- **SC5.** 한 어댑터가 실패해도(예: yt-dlp 자막 없음) 나머지 어댑터 결과만으로 리포트 생성이 성공한다.
- **SC6.** `/research-followup "X도 찾아줘"` 실행 시 해당 세션 폴더의 `session.md`에 새 답변과 새로 수집된 자료가 append된다.
