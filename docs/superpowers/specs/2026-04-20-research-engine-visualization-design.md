# research-engine — Visualization Design Spec

**Status:** Approved (brainstorming phase)
**Date:** 2026-04-20
**Owner:** harry@qplace.kr
**Target version:** 0.3.0

## 1. 목적 (Purpose)

현재 `/research` 는 인용 포함 마크다운 리포트만 출력한다. 본 스펙은 **시각화 능력**을 별도 경로로 추가한다 — 데이터 차트(기본), Mermaid 다이어그램(옵션), Marp 기반 슬라이드 덱(옵션).

### 1.1 Use Cases

- **V1.** 완성된 리서치 세션의 벤치마크·수치 비교를 차트 PNG 로 추출 → README.md 에 인라인 (로컬만; Notion 업로드는 v2 후속).
- **V2.** 리포트 상세 분석의 구조·흐름·타임라인을 Mermaid 다이어그램으로 요약 → GitHub/Notion 에서 네이티브 렌더 (Mermaid 는 마크다운 텍스트라 기존 Notion push 가 자동 반영).
- **V3.** 발표·공유용 `.pptx` / `.pdf` 슬라이드 덱 생성 — Marp 마크다운 기반, 편집 가능.

### 1.2 Non-goals

- **어댑터 컨트랙트 변경 금지** — 시각화는 완성된 세션을 입력으로 받는 포스트-호크 처리만 담당.
- **커버/히어로 이미지 자동 생성 안 함** — 이미지 모델 호출은 범위 밖.
- **Notion 에 차트 PNG 업로드 안 함 (v1)** — Mermaid 는 마크다운 텍스트라 자동 반영되지만, 차트 PNG · `.pptx` 는 로컬 산출물로 한정. v2 에서 필요해지면 추가.
- **`/research` 파이프라인 수정 없음** — 기존 사용자 경험 완전 보존.

## 2. 인터페이스

### 2.1 신규 슬래시 커맨드 `/research-visualize`

```
/research-visualize <slug> [--slides] [--diagrams] [--fresh]
/research-visualize                         # slug 생략 → find_latest_session.sh
```

| 플래그 | 효과 |
|---|---|
| (없음) | 데이터 차트 PNG 만 생성 + README 의 `## 시각 자료` 섹션 삽입 |
| `--diagrams` | 추가로 Mermaid 다이어그램 텍스트 블록을 README 에 삽입 |
| `--slides` | 추가로 `slides.md` + `slides.pptx` + `slides.pdf` 생성 (Marp) |
| `--fresh` | 기존 `figures/`, `slides.*`, README `## 시각 자료` 섹션을 덮어씀 |

**Notion 동기화**: 자동 트리거하지 않음. Mermaid 는 이미 README 마크다운 안에 들어가므로 사용자가 이후 `bash scripts/push_to_notion.sh <dir>` 를 수동 실행하면 반영됨. 차트 PNG 는 Notion 업로드 v1 에서 제외.

### 2.2 출력 레이아웃

```
research/<slug>/
  README.md               ← <!-- viz:begin --> … <!-- viz:end --> 마커 블록 내부에
                            ## 시각 자료 (charts) + ## 구조 다이어그램 (mermaid, --diagrams 시)
                            (idempotent: 재실행 시 블록 내부만 교체, 그 외 본문 불변)
  figures/
    chart-01-<short>.png
    chart-01-<short>.meta.json   ← 원본 차트 스펙 + evidence
    chart-02-<short>.png
    ...
  slides.md               ← Marp 원본 (--slides 시)
  slides.pptx             ← Marp CLI 렌더 (--slides 시)
  slides.pdf              ← Marp CLI 렌더 (--slides 시)
  viz.json                ← 시각화 세션 메타 (생성된 차트·다이어그램 목록, 타임스탬프, failures)
```

## 3. 설계 원칙

1. **환각 방지**: 차트의 모든 숫자는 `sources.json` 에 인덱싱된 원문 인용(verbatim quote) 에 존재해야 한다. extractor 프롬프트가 하드 제약으로 이를 강제.
2. **추적성**: 각 차트/다이어그램은 `source_ids` 를 보존 — `.meta.json` 과 README 캡션 양쪽에.
3. **격리**: `/research` 메인 파이프라인 무변경. 시각화 실패는 리서치 결과에 영향 없음.
4. **멱등성**: 같은 세션에 같은 플래그로 재실행하면 노-옵. `--fresh` 로만 강제 갱신.
5. **부분 실패 허용**: 차트 하나가 실패해도 나머지 + 다이어그램 + 슬라이드는 계속.
6. **최소 의존성**: 기본 경로는 `curl`+`jq`+`python3` (이미 요구사항). `npx` 는 `--slides` 에서만.

## 4. 아키텍처

```
commands/research-visualize.md          (오케스트레이터)
  │
  ├─ V1. Load & Validate
  │    scripts/load_session.sh <slug>
  │    → JSON: { slug, report_dir, readme_content, sources[] }
  │    → exit 1 if missing
  │
  ├─ V2. Extract charts  (always)
  │    Agent: agents/visualizer-extractor.md
  │    input:  {readme_content, sources}
  │    output: charts[] (JSON spec per lib/chart_spec_contract.md)
  │
  ├─ V3a. Render charts
  │    for each chart:
  │      scripts/render_chart.sh <spec.json> <out.png>
  │      → QuickChart HTTP call, write PNG + .meta.json
  │      → on failure: record in viz.json.failures[], continue
  │
  ├─ V3b. Extract diagrams  [--diagrams]
  │    Agent: agents/visualizer-diagrammer.md
  │    output: diagrams[] (mermaid text blocks + placement hints)
  │
  ├─ V3c. Build slide deck  [--slides]
  │    Agent: agents/visualizer-deck.md
  │    output: slides.md (Marp markdown, referencing figures/*.png)
  │    scripts/render_slides.sh
  │      → npx -y @marp-team/marp-cli@latest slides.md --pptx --pdf --allow-local-files
  │      → on npx/network failure: keep slides.md, skip pptx/pdf, warn
  │
  └─ V4. Patch README & persist
       scripts/patch_readme.sh
         → replace or append `<!-- viz:begin --> ... <!-- viz:end -->` block
         → includes ## 시각 자료 subsection (charts) + optional ## 구조 다이어그램 (mermaid blocks)
       write viz.json
       echo summary + paths
```

### 4.1 신규 파일 (총 ~9)

| 경로 | 역할 |
|---|---|
| `commands/research-visualize.md` | 슬래시 커맨드 오케스트레이터 |
| `agents/visualizer-extractor.md` | 차트 스펙 추출 서브에이전트 |
| `agents/visualizer-diagrammer.md` | Mermaid 다이어그램 생성 서브에이전트 |
| `agents/visualizer-deck.md` | 슬라이드 덱 (`slides.md`) 생성 서브에이전트 |
| `scripts/load_session.sh` | 세션 디렉토리 검증 + JSON 컨텍스트 조립 |
| `scripts/render_chart.sh` | 차트 스펙 → QuickChart PNG |
| `scripts/render_slides.sh` | Marp CLI 호출 wrapper |
| `scripts/patch_readme.sh` | README 의 viz 마커 블록 in-place 교체 |
| `lib/chart_spec_contract.md` | 차트 스펙 JSON 스키마 문서 |

### 4.2 수정 파일

- `README.md` — 플러그인 사용법에 `/research-visualize` 섹션 + 선택 의존성(npx) 추가
- `CHANGELOG.md` — 0.3.0 엔트리 (Added only)
- `DEVELOPMENT.md` — 새 bats 테스트 목록 언급
- `tests/fixtures/sample-session/` — 미니 README + sources.json 추가

### 4.3 건드리지 않는 파일

- `commands/research.md`, `commands/research-followup.md`
- `agents/*-adapter.md`
- `scripts/push_to_notion.sh`, `scripts/yt_fetch.sh`, `scripts/slugify.sh`, `scripts/classify_url.sh`, `scripts/cache_key.sh`, `scripts/find_latest_session.sh`
- `lib/adapter_contract.md`, `lib/report_sections.md`

## 5. 차트 스펙 컨트랙트 (`lib/chart_spec_contract.md`)

`visualizer-extractor` 가 반환하는 JSON:

```json
{
  "charts": [
    {
      "id": "c1",
      "title": "주요 LLM 벤치마크 비교 (MMLU)",
      "kind": "bar | line | pie | scatter | horizontal_bar | table",
      "rationale": "§상세분석에서 4개 모델의 벤치마크 수치가 나열 — 비교 차트로 시각화 용이",
      "data": {
        "labels": ["GPT-4o", "Claude Opus 4.7", "Gemini 2.5", "Llama 4"],
        "datasets": [
          { "label": "MMLU (%)", "values": [88.7, 91.2, 86.4, 82.1] }
        ]
      },
      "evidence": [
        { "source_id": 3, "quote_verbatim": "Claude Opus 4.7 scored 91.2 on MMLU..." },
        { "source_id": 5, "quote_verbatim": "GPT-4o reaches 88.7 on MMLU..." }
      ],
      "axis": { "x": "모델", "y": "점수 (%)" }
    }
  ],
  "rejected": [
    { "reason": "수치 없이 '크게 향상되었다' 서술만 — 차트화 불가", "excerpt": "..." }
  ]
}
```

### 5.1 하드 제약 (extractor 프롬프트에 명시)

1. `data.datasets[].values[]` 의 모든 숫자는 **반드시** 같은 차트의 `evidence[].quote_verbatim` 중 하나에 문자열로 존재. 없으면 차트 거부.
2. `evidence[].source_id` 는 `sources.json` 에 존재하는 정수 id.
3. "추정치", "약", "대략" 같은 모호 수치 금지. 숫자 주변 맥락을 그대로 인용.
4. 차트 최대 5개 (기본). 0개도 정상.
5. 한 차트당 데이터 포인트 ≤ 12개.
6. `kind` 는 명시된 6종 중 하나만. 그 외 거부.

### 5.2 렌더링 매핑

`scripts/render_chart.sh` 가 JSON 스펙을 Chart.js config 로 변환:

- `kind: "bar"` → `type: "bar"`, `horizontal_bar` → `type: "bar"` + `indexAxis: "y"`
- `kind: "line"` → `type: "line"` + smooth tension 0.2
- `kind: "pie"` → `type: "pie"`
- `kind: "scatter"` → `type: "scatter"` (datasets[].values 는 `[{x,y},...]` 형식 기대)
- `kind: "table"` → QuickChart 의 `chart: "table"` 프리뷰 사용

QuickChart 호출: `https://quickchart.io/chart?c=<url-encoded-config>&width=800&height=400&backgroundColor=white&version=4`

### 5.3 메타 파일

각 차트당 `chart-NN-<slug>.meta.json`:
```json
{
  "id": "c1",
  "title": "...",
  "spec": { /* 원본 JSON 스펙 */ },
  "rendered_at": "2026-04-20T12:34:56Z",
  "quickchart_url": "https://quickchart.io/chart?c=...",
  "source_ids": [3, 5]
}
```

## 6. 다이어그램 (`--diagrams`)

`visualizer-diagrammer` 반환:

```json
{
  "diagrams": [
    {
      "id": "d1",
      "title": "Claude Computer Use — 3가지 경로",
      "placement": "after_section:§4.1",
      "mermaid": "flowchart LR\n  A[User] --> B{...}\n  ...",
      "evidence_src_ids": [4, 10, 22]
    }
  ]
}
```

**제약**:
- 허용 차트 종류: `flowchart`, `sequenceDiagram`, `classDiagram`, `timeline`, `gantt`. 그 외 거부.
- 최대 3개.
- 각 다이어그램은 ` ```mermaid ` 코드블록으로 README 에 삽입. 아래에 `> 출처: [4][10][22]` 캡션 한 줄.
- 렌더 파일 저장 없음 (Mermaid 텍스트만).

## 7. 슬라이드 (`--slides`)

`visualizer-deck` 가 `slides.md` 생성:

```markdown
---
marp: true
theme: default
paginate: true
---

# {{report_title}}
*{{slug}} · {{iso_date}}*

---

## TL;DR
- {{bullet from §요약}}
- ...

---

## 핵심 포인트 (1/2)
- {{point 1}}
- {{point 2}}

---

<!-- 차트/다이어그램을 각 1 슬라이드 -->
![bg fit](figures/chart-01-<slug>.png)

---

## Sources
1. {{title}} — {{url}}
```

**덱 구조**:
1. 타이틀 슬라이드 (1)
2. TL;DR (1)
3. 핵심 포인트 (2–3, 6 bullet/슬라이드 상한)
4. 섹션 요약 (섹션당 1, 최대 10)
5. 차트 (각 1 슬라이드, `![bg fit]`)
6. 다이어그램 (각 1 슬라이드, ` ```mermaid ` 블록)
7. Sources (1)

**렌더링**: `scripts/render_slides.sh` 가 `npx -y @marp-team/marp-cli@latest slides.md --pptx --pdf --allow-local-files` 실행. `npx`/네트워크 실패 시 `slides.md` 만 보존, `viz.json.failures[]` 에 기록.

**이미지 경로**: 슬라이드의 이미지 참조는 `figures/...` 상대경로 (Marp `--allow-local-files` 필수).

## 8. Notion 미러링 처리

- **Mermaid 다이어그램**: README.md 에 삽입된 ` ```mermaid ` 블록은 기존 `push_to_notion.sh` 의 `md_to_blocks` 파서가 자동 처리 → Notion 의 Mermaid 네이티브 렌더로 반영. **추가 작업 없음**.
- **차트 PNG**: v1 범위 밖. `push_to_notion.sh` 는 건드리지 않음. README 에 삽입된 `![](figures/...)` 는 현재 md_to_blocks 파서가 이미지 블록을 생성하지 않고 무시/드롭하므로 Notion 페이지는 깔끔하게 유지됨 (차트는 Notion 에서 안 보이고 로컬 README/GitHub 에서만 보임). 이 한계를 플러그인 README 에 명시.
- **`.pptx` / `.pdf`**: v1 범위 밖. 로컬 파일로만.

v2 확장 여지: `/research-visualize --sync-notion` 플래그 또는 `scripts/push_to_notion.sh --with-figures` 서브커맨드로 PNG 업로드 추가.

## 9. 실패 정책

| 실패 지점 | 동작 |
|---|---|
| `<slug>` 디렉토리 없음 / README.md 누락 / sources.json 누락 | `load_session.sh` exit 1, 사용자 안내 메시지 |
| extractor 가 빈 `charts: []` 반환 | 정상 종료, README 에 `## 시각 자료` 섹션 생성 안 함, `viz.json.note = "no_chartable_data"` |
| 차트 evidence 검증 실패 | 해당 차트 skip, stderr 경고, `viz.json.failures[]` 기록. 다른 차트 계속 |
| QuickChart HTTP 오류 (timeout / 4xx / 5xx) | 해당 차트 skip + `failures[]`. 다른 차트·다이어그램·슬라이드 계속 |
| `--diagrams` 없이 diagrammer 가 실행됐을 때 | 실행되지 않음 (플래그 분기) |
| `--slides` + Marp CLI 실패 | `slides.md` 보존, `.pptx/.pdf` 포기, 경고 메시지 |
| `--fresh` 없는 재실행 | 기존 `chart-NN-*.png` 존재 시 skip (멱등), `patch_readme.sh` 는 마커 블록만 교체 (마커 외 본문 무변경) |

**보장 사항**: `/research-visualize` 는 exit 0 가 "모든 것 성공" 이 아니라 "치명 실패 없음". 사용자는 `viz.json.failures[]` 와 stderr 로 세부 파악.

## 10. 테스트

### 10.1 Bats 단위 테스트

| 파일 | 대상 |
|---|---|
| `tests/bats/test_load_session.bats` | slug 없음 / README 없음 / sources.json 없음 각 경우 exit 1, 정상 케이스에서 JSON 조립 |
| `tests/bats/test_patch_readme.bats` | 마커 없을 때 append, 있을 때 in-place 교체, 마커 외 본문 불변, 멱등성 |
| `tests/bats/test_render_chart.bats` | mock QuickChart (curl 을 함수 대체) — 200 정상, 404 skip+failures 기록, 스키마 위반 스펙 거부 |

### 10.2 Fixture

`tests/fixtures/sample-session/` 추가:
- `README.md` — §요약 + 숫자 두 개 포함한 §상세분석 (차트 추출 가능)
- `sources.json` — 2개 sources
- `intent.json`

### 10.3 수동 수락 테스트

`tests/acceptance/research-visualize.md`:
- (1) 실제 `/research <url>` 로 세션 생성
- (2) `/research-visualize <slug>` → figures/ 확인, README 섹션 확인
- (3) `/research-visualize <slug> --diagrams --slides` → Mermaid 블록 + `.pptx` 열어보기
- (4) 재실행 멱등성 + `--fresh` 동작
- (5) `scripts/push_to_notion.sh <dir>` 재실행 시 Mermaid 가 Notion 에 반영되는지

## 11. 의존성

| 툴 | 상태 | 용도 |
|---|---|---|
| `curl` | 기존 | QuickChart HTTP 호출 |
| `jq` | 기존 | 차트 스펙 스키마 검증 |
| `python3` | 기존 | URL 인코딩 (`urllib.parse`) |
| `npx` (Node 18+) | **신규, 선택** | Marp CLI 렌더 (`--slides` 쓸 때만) |

README 의 Requirements 섹션에 선택 의존성으로 한 줄 추가.

## 12. 버저닝 & 릴리스

- 버전: **0.3.0** (마이너 — 순수 추가, 파괴적 변경 없음)
- CHANGELOG.md 에 Added 섹션만:
  - `/research-visualize` slash command
  - Four new scripts, four new subagents, one new lib contract
  - Notion: Mermaid diagrams now mirror automatically via existing markdown path
- Git tag `v0.3.0` 후 marketplace 갱신

## 13. 미해결 항목 (v2 후속)

- 차트 PNG 를 Notion 에 업로드 (`--sync-notion` 플래그)
- 어댑터 컨트랙트에 `datasets[]` optional 필드 추가 — github-adapter 가 star 히스토리를, arxiv-adapter 가 benchmark 표를 직접 제공
- 커버/히어로 이미지 자동 생성
- 슬라이드 테마 커스터마이징 (`--theme <name>`)
- `/research --visualize` 통합 플래그 (한 커맨드로 끝내고 싶을 때)
