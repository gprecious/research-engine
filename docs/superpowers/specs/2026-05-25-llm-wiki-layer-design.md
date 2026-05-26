---
title: research-engine — LLM Wiki 레이어 설계
slug: 2026-05-25-llm-wiki-layer-design
created: 2026-05-25
updated: 2026-05-26
status: draft (revised after claude+codex cross-review)
---

# research-engine — LLM Wiki 레이어

research-engine이 만들어 둔 raw 리서치 세션(`research/`)을 **상호연결된 LLM 위키**로 합성·발행하는 한 겹을 얹는다. prior-art(Karpathy "LLM Wiki" 패턴, Quartz 발행, Obsidian vault)를 research-engine의 기존 자산(92 세션 + 어댑터 ingestion)에 매핑한 단일 spec.

배경: "다른 AI 엔지니어들이 LLM 위키를 어떻게 만들었는가"를 3축(YouTube / Substack·블로그 / 툴 생태계)으로 병렬 조사한 결과, 2026-04 Karpathy gist 이후 **불변 raw → LLM 합성 wiki → 평문 스키마(헌법)** 3계층 + **ingest / query / lint** 3연산 + **Obsidian 호환 마크다운 vault + Quartz 발행**이 널리 채택되는 실용 패턴으로 확인됐다. (단일 "정설"이라기보다 이 spec이 채택하는 패턴이다. A-MEM 등 더 정교한 agentic-memory 기법은 top-k 후보 축소 아이디어만 차용하고 memory-evolution/auto-merge는 채택하지 않는다.) research-engine은 이미 그 패턴의 "ingestion mouth"를 갖고 있으므로, 새 시스템이 아니라 **합성·링크·발행 레이어만** 추가한다.

> **개정 이력**: 초안은 stage-1 임베딩(transformers.js) → stage-2 LLM 판정의 "2단계 링크"를 채택했으나, claude+codex 교차리뷰에서 (a) 무거운 런타임 의존성(onnxruntime+모델 수백MB)과 플러그인 배포 스토리 부재, (b) "디스크 쓰기 → reindex → 판정 → 재apply"의 치킨-에그가 본문 중복을 유발한다는 지적을 받아, **MVP는 카탈로그 기반 LLM 직접 링크**로 전환하고 임베딩 2단계는 페이지 수가 카탈로그 직접판정 한계를 넘을 때 후속 spec으로 승격한다.

## 1. 한 줄 요약

`research/`의 세션들을 소스로 **Claude Code/Codex가 concept·entity 위키 페이지를 생성하고, `index.md` 카탈로그를 근거로 기존 페이지와의 진짜 개념적 연결만 `[[wikilink]]`로 걸며, 단일 멱등 apply로 페이지·index·log를 갱신하고, `lint`로 무출처·미해결 인용·끊긴 링크·고아·중복을 잡고, Quartz로 정적 사이트를 발행**하는 `/wiki` 명령군을 research-engine 플러그인에 추가한다.

## 2. 목적

- **재발견 비용 → 복리 지식**: 92세션에 흩어진 같은 개념(attention, MoE, RAG, agent harness …)을 개념·엔티티 페이지로 한 번 합성. 이후 질의는 위키에서 인용과 함께 즉답.
- **기존 자산 100% 활용 + dogfooding**: research-engine 어댑터가 이미 YouTube/Substack/블로그/arXiv를 ingest. 위키는 그 출력 위에서만 동작.
- **회의론("AI 슬롭") 정면 대응**: raw 티어는 **절대 수정하지 않고** AI가 쓰는 `wiki/`와 분리. 모든 사실 주장은 출처 세션(`sources[]`)에 근거를 두고, `lint`가 무출처·미해결 인용을 표시.
- **발행 가능한 지식 정원**: Quartz로 graph·backlink·전문검색 정적 사이트를 발행.

## 3. 스코프

### In-scope
- 신규 디렉토리 `wiki/`(content) + `wiki/_index/`(ingest 임시 plan-*.json, gitignore)
- 신규 헌법 파일 `wiki/AGENTS.md`(에이전트 동작 규칙·스키마)
- 신규 슬래시 명령 `commands/wiki.md`(액션: `ingest` / `query` / `lint` / `publish`)
- 신규 로직 `lib/wiki/`(slug·frontmatter·index/log·apply·lint) + vitest 단위테스트
- 신규 셸 글루 `scripts/wiki_publish.sh`(Quartz 빌드+배포)
- **카탈로그 기반 LLM 직접 링크**(index.md를 LLM에 제공 → 진짜 연결만 선택, apply 전에 결정)
- 기존 92세션 일괄 시드(`/wiki ingest --all`) + `/wiki lint`
- Quartz 발행(`/wiki publish`) + 빌드 smoke + 배포(hetzner LXC 또는 GitHub Pages)
- Codex 패리티: `skills/research-engine/SKILL.md`에 위키 워크플로 추가

### Out-of-scope (이번 spec 제외 — 후속)
- **임베딩 사이드카 / 2단계(임베딩→판정) 링크** — 카탈로그 직접판정이 한계(수천 페이지+)에 닿으면 후속 spec. 무거운 네이티브 의존성·모델캐시·배포 게이트를 그 spec에서 다룬다.
- **자동 연속 유지(cron/hook auto-ingest)** — MVP는 수동 `/wiki ingest --new`.
- **draft→사람 승인(promote) 게이트** — 라이트 가드레일. `confidence`는 표기만.
- **모순(contradiction) lint / community detection / memory-evolution** — 후속.
- **Notion 위키 발행** — 발행은 Quartz. 기존 `push_to_notion.sh`는 research 세션용 유지.
- **multi-user / 공유 vault** — 로컬 single-user 가정.
- raw `research/` 세션 파일 변경 — 읽기 전용.

## 4. 아키텍처 & 데이터 흐름

```
research/  [기존, gitignored]           ← raw 불변 소스 티어
  YYYY-MM-DD-<slug>/{README.md, sources.json, intent.json}
        │  /wiki ingest  (LLM 합성 + 카탈로그 기반 링크)
        ▼
wiki/  [신규, 로컬 vault]                ← LLM 합성 티어
  concepts/<slug>.md                    ← 개념 페이지
  entities/<slug>.md                    ← 엔티티 페이지(people·orgs·models·papers·tools)
  index.md                              ← 카탈로그/MOC (재생성; 링크 판정의 근거로 LLM에 제공)
  log.md                                ← append-only 인제스트 원장(소스 단위 1줄)
  AGENTS.md                             ← 헌법(스키마·규칙)
  _index/  [gitignore]                  ← ingest 임시 plan-*.json (재생성 가능)
        │  /wiki publish
        ▼
Quartz site  [QUARTZ_DIR = vault 밖]    ← 정적 발행(graph·backlink·검색)
```

- **읽기 전용 raw**: ingest는 `research/`를 읽기만 한다.
- **단일 apply**: LLM이 페이지 본문과 링크(`links[]`)를 **디스크에 쓰기 전에** 모두 확정 → `apply.mjs`가 **한 번만** 실행(검증-전체 → 쓰기-전체 → log-1회, tmp+rename 원자 교체). 더블-apply/치킨-에그 없음. perspective 섹션 키는 `pagePlan.source`. 링크는 soft-link 허용(미존재 페이지=향후 생성, lint가 broken-link로 표시).
- **상태는 평문 파일**: `index.md` 카탈로그 + `log.md`(소스 단위 정확 1줄). 링크 판정의 근거는 임베딩이 아니라 `index.md`를 LLM에 통째로 주는 것.

## 5. 저장 레이아웃 & git 정책

- `wiki/`는 research-engine repo 작업 디렉토리 안에 위치하되 research-engine git에는 **커밋하지 않는다**(`.gitignore`에 `wiki/`). `research/`와 동일 정책 — 개인 콘텐츠가 플러그인 배포에 섞이지 않게.
- durability/발행: `wiki/`를 자체 nested git repo(`git init wiki/`)로 둘 수 있다(권장, 선택).
- 플러그인에 ship: `commands/wiki.md`, `lib/wiki/`, `scripts/wiki_publish.sh`, 헌법 템플릿 `lib/wiki/AGENTS.template.md`(첫 ingest 시 `wiki/AGENTS.md`로 복사).
- `_index/`(임시 plan)는 gitignore.
- **Quartz**: `QUARTZ_DIR`는 vault 밖(기본 `<repo>/wiki-site/` 또는 `$HOME`)에 둔다. `wiki/`는 Quartz의 content source로만 취급(.quartz를 vault 안에 두지 않음 — nested git/ignore 충돌 방지).

## 6. 페이지 스키마 — `wiki/AGENTS.md`(헌법)

**concept/entity 페이지 frontmatter**
```yaml
---
type: concept | entity
title: Mixture of Experts          # 표시 제목 (한글 가능)
slug: mixture-of-experts           # ASCII kebab만. 한글 금지(아래 정책)
aliases: [MoE, 전문가 혼합]         # 한글 alias 허용
sources: [research/2026-04-27-moe-llm-routing-improvements-2025, …]  # 근거 세션
related: ["[[attention-mechanism]]", "[[transformer]]"]  # 링크 단일 신뢰원
confidence: high | medium | low    # 표기만 (라이트)
created: 2026-05-25
updated: 2026-05-26
---
```

**본문 구조** (소스별 섹션 — merge 멱등성의 핵심):
```
## TL;DR
<개념 한 줄 요약>

## 출처별 관점
### research/2026-04-27-moe-...
- ... [1]      ← [n] = 이 세션 sources.json 의 n번 (세션-로컬 번호 → merge에도 안정)
### research/2026-05-01-moe-followup
- ... [2]

## 관련 개념        ← related frontmatter 에서 렌더링(재생성). 직접 편집 안 함
- [[attention-mechanism]]
```

**규칙(헌법 발췌)**:
1. 1 페이지 = 1 concept 또는 1 entity. raw 절대 수정 금지.
2. **slug = ASCII kebab-case(`^[a-z0-9]+(-[a-z0-9]+)*$`)**. 한글은 title·aliases에만. (영문 개념명을 slug로; 적절한 영문명이 없으면 romanize, 그래도 없으면 해시 suffix.)
3. frontmatter 필수: `type, title, slug, sources, related, created, updated`.
4. **모든 사실 주장은 `### research/<slug>` 섹션 안에서 그 세션의 `[n]`으로 인용**. 세션-로컬 번호라 merge로 깨지지 않는다. 무출처 주장 금지.
5. 링크 신뢰원 = frontmatter `related`. 본문 `## 관련 개념`은 related에서 **렌더링**(중복 누적 금지).
6. 링크는 `index.md` 카탈로그에 실재하는 페이지와의 **진짜 개념적 연결**만. 표면 키워드 겹침으로 링크하지 않는다.

## 7. `/wiki` 명령 계약 (`commands/wiki.md`)

기존 명령 컨벤션(frontmatter: description/argument-hint/allowed-tools, `${CLAUDE_PLUGIN_ROOT}` 글루) 준수. 단일 명령 + 액션:

| 액션 | 입력 | 동작 계약 |
|---|---|---|
| `ingest` | `<slug> \| --all \| --new` | 세션 읽기 → `index.md` 카탈로그 읽기 → 엔티티·개념 추출 + **카탈로그 내 실재 페이지와의 링크 선택**(apply 전 확정) → pagePlan(JSON) → `apply.mjs` **단일 실행** |
| `query` | `"<질문>"` | 카탈로그 + grep 후보 → 위키 페이지에서 인용 합성(읽기 전용). `--file` 환류는 MVP out-of-scope(후속) |
| `lint` | `[--fix]` | 무출처·미해결인용·끊긴링크·고아·중복(name) 보고. `--fix`는 MVP에서 보고+안내만(결정적 자동수정은 후속) |
| `publish` | `[--deploy]` | `wiki/`→Quartz 빌드(+index 존재 smoke). `--deploy`면 배포 |

**ingest 의미**:
- `--new`: `log.md`에 (정확 매칭으로) 없는 세션만.
- `--all`: 모든 세션. 이미 있는 소스는 기본 skip(=`--new`와 동치). 강제 재합성이 필요하면 `--all --rebuild`(merge가 아니라 해당 소스 섹션 교체)로 별도.

## 8. 카탈로그 기반 직접 링크 (임베딩 대체)

```
ingest 중, 디스크에 쓰기 전:
  1. wiki/index.md (기존 페이지 slug+title 카탈로그)를 LLM 컨텍스트에 제공
  2. LLM이 각 신규/갱신 page에 대해, 카탈로그에서 진짜 개념적으로 연결되는
     기존 page slug만 골라 links[]에 넣는다 (표면 겹침 배제 — 판정이 곧 stage-2)
  3. links 가 확정된 pagePlan 으로 apply 1회 실행
```
- 임베딩·reindex·cosine·candidates_cli **불필요**. 무거운 의존성·치킨에그·차원 불일치 NaN 문제 모두 제거.
- 카탈로그가 매우 커지면(LLM 컨텍스트 한계) 후속 spec에서 임베딩 후보축소를 도입. 그 전까지 카탈로그(수백~수천 항목, 페이지당 slug+title 한 줄)는 충분히 들어간다.

## 9. 라이트 가드레일

- **강제**: 사실 주장은 `### research/<slug>` 섹션의 세션-로컬 `[n]` 인용. `lint`:
  - `unsourced`: 본문에 주장이 있는데 `sources[]`가 빔.
  - `citation-unresolved`: 본문 `[n]` 인용에 대응 섹션/sources가 없거나, `### research/<slug>` 섹션이 frontmatter `sources`에 없음.
  - `broken-link`: `related`의 `[[slug]]` 대상이 vault에 없음(soft-link 표시).
  - `orphan`: 인바운드·아웃바운드 링크 모두 없음.
  - `duplicate-name`: title·alias를 정규화(NFKC+trim+lower)·통합한 이름이 둘 이상 페이지에서 충돌.
- **표기**: `confidence` — 승인 게이트 없음.
- **분리**: AI가 쓰는 `wiki/`와 raw `research/` 물리 분리.
- `query --file` 환류는 MVP out-of-scope(환각 전파 위험 + 다중 source 매핑 미정 — 후속 spec).

## 10. 시드 & 신규 연동
- 초기 시드: `/wiki ingest --all` → 92세션(이미 처리분은 정확매칭 skip) → `/wiki lint`로 정리.
- 신규 연동: `/research` 후 사용자가 `/wiki ingest --new`(MVP 수동). 자동화는 후속.

## 11. Quartz 발행
- `QUARTZ_DIR`(vault 밖)에 Quartz 체크아웃. `wiki/{concepts,entities,index.md}`를 content로 복사(raw 제외). `npx quartz build` 후 **`public/index.html` 존재를 smoke로 검증**. `--deploy`면 `WIKI_DEPLOY_CMD`(hetzner rsync 또는 gh-pages).

## 12. 테스트 전략
- **vitest** (`lib/wiki/*.test.mjs`): slug(ASCII+fallback), frontmatter 스키마(slug ASCII regex), index 재생성, **isIngested 정확 라인매칭**, **apply 멱등성/원자성/섹션merge/related 렌더링**, lint 규칙(무출처·미해결인용·끊긴링크·고아·중복).
- **bats** (`tests/research-engine/wiki.test.sh`): apply CLI(생성·merge 무중복·log 1줄)·lint CLI·publish smoke(quartz 없으면 안내) 계약.
- TDD Red→Green. `package.json` `test:unit`(lib 전체)·`test:bats`에 wiki 추가.

## 13. 단계(phasing)
1. 헌법 템플릿 + slug/frontmatter/index_log + gitignore + 의존성(`yaml`만)
2. `apply.mjs`(원자·섹션merge·단일) + `/wiki ingest <slug>`(카탈로그 링크) + bats
3. `--all`/`--new`(정확매칭) 일괄 시드
4. `lint`(+CLI) + `/wiki lint`
5. `/wiki query`(+환류 가드레일)
6. `/wiki publish`(Quartz, vault 밖, smoke) + Codex SKILL 패리티 + 버전 bump

## 14. 미해결 / 리스크
- **`wiki/` git 정책**: gitignore(로컬). 커밋 원하면 변경.
- **카탈로그 컨텍스트 한계**: 페이지 수천+ 시 index.md가 LLM 컨텍스트를 압박 → 후속 임베딩 spec 트리거.
- **대량 일괄 ingest 시간/비용**: 이미 처리분은 정확매칭 skip으로 재개.
- **개념 분류 폭주**(~50 엔티티+): 헌법 병합 규칙 + `lint` duplicate 탐지로 1차 대응(자동 merge는 후속).
- **환각 전파**: `sources[]` + `### research/<slug>` 세션-로컬 인용 + `citation-unresolved` lint + query 환류 가드레일로 1차 방어(라이트 한계 인지).
- **lint는 모순(contradiction)을 잡지 못함**: 의도적 out-of-scope.
- **apply 원자성 범위**: 파일 단위 tmp+rename 원자 쓰기 + 사전검증(invalid 입력은 어떤 파일도 안 씀). 단 여러 파일 중간 I/O 실패 시 부분 반영 가능 — 전체 트랜잭션은 아님(staging+rollback은 후속).

## 15. 결정 로그 (확정)
- 접근: **A — research-engine 위 wiki 레이어**.
- vault 위치: **repo 내 `wiki/`** (gitignore=로컬).
- 발행: **Quartz**(QUARTZ_DIR = vault 밖, build smoke).
- 가드레일: **라이트** (`sources[]` + 세션-로컬 인용 + `lint`).
- 링크: **카탈로그 기반 LLM 직접 링크**(임베딩 2단계는 후속 spec — claude+codex 교차리뷰 권고 수용).
- apply: **단일 실행**(검증-전체 → 쓰기-전체 → log-1회, tmp+rename), 섹션 구조 merge(키=`pagePlan.source`), `related` 링크 단일 신뢰원, soft-link 허용.
- slug: **ASCII kebab 고정**(한글은 title/aliases).
- 의존성: `yaml`만(런타임 임베딩 의존성 제거).
- 후속 spec(MVP 제외): `query --file` 환류, `lint --fix` 결정적 자동수정, 임베딩 후보축소(2단계 링크), contradiction lint, 자동 연속 ingest.
- 2차 교차리뷰(claude=sound / codex=needs-changes) 수렴 정제 반영: perspective 키잉·parseBody 앵커링·tmp+rename·citation⊆sources·duplicate-name 정규화.
