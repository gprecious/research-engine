---
title: research-engine — LLM Wiki Obsidian 타게팅 + Librarian (dream/evolve) 설계
slug: 2026-06-09-llm-wiki-librarian-design
created: 2026-06-09
updated: 2026-06-09
status: draft (brainstorming approved)
builds_on: 2026-05-25-llm-wiki-layer-design
---

# research-engine — LLM Wiki → Obsidian 단일 글로벌 vault + Librarian

기존 `/wiki` 레이어([[2026-05-25-llm-wiki-layer-design]])를 (1) **harry Obsidian vault 안 단일 글로벌 위키**로 타게팅하고 `#ai-generated` 태깅으로 사용자 노트와 분리하며, (2) 주기적으로 위키를 최신화·태깅·연결·정리하고 research-engine 의 **dream/evolve** 를 위키에 적용하는 **librarian** 을 추가한다. confident-wrongness·토큰 폭발·second-brain graveyard 라는 prior-art 의 3대 실패 모드를 promotion gate + 월간 증분 + 티어드 자동화로 회피한다.

## 1. 한 줄 요약

`/wiki ingest` 가 어느 프로젝트에서 실행돼도 **harry/LLM-Wiki** 한 곳에 in-place 누적(이름 기반 vault 해석)되고, 모든 생성 페이지는 `tags: [ai-generated, llm-wiki, <type>]` 로 태깅되며, 월간(또는 수시) `/wiki librarian` 이 7-stage health-check 를 돌려 **안전한 수정은 자동 적용·위험한 산출(신규 페이지·cross-link·dream synthesis·evolve 변경)은 `_drafts/` 로 격리(promotion gate)**, dream 은 cross-wiki 패턴을 `synthesis/` 와 gap 리서치 질문 `_todos/` 로, evolve 는 위키 헌법·librarian 휴리스틱을 점진 개선한다. Obsidian Sync 가 전 기기·모바일에 콘텐츠를 전파한다.

## 2. 배경 — 무엇이 이미 있고 무엇을 더하는가

research-engine 0.17.0 은 이미 Karpathy 3-layer(`research/`=raw 불변 / `wiki/{concepts,entities}`=LLM 저작 / `wiki/AGENTS.md`=헌법) + `index.md`·`log.md` + `ingest|query|lint|publish` 4연산을 갖췄다(`commands/wiki.md`, `lib/wiki/{apply,lint,frontmatter,index_log,slug}.mjs`, `scripts/wiki_publish.sh`). 단:

- 위키가 **프로젝트 cwd 의 `wiki/`** 에 갇힌다(글로벌·Obsidian·동기화 없음).
- `lint` 는 **탐지·보고만**(`--fix` 는 안내만, 결정적 자동수정 미구현).
- **주기적 유지(librarian)·dream/evolve 위키 적용·promotion gate·태깅·temporal 분리**가 없다.

이 spec 은 새 시스템이 아니라 **위 4연산을 재사용**하고 위 빈 곳만 채운다(reuse-don't-reinvent).

## 3. 확정된 설계 결정 (brainstorming)

| # | 결정 | 값 |
|---|------|----|
| D1 | 토대 | research-engine `/wiki` **확장** |
| D2 | 범위/위치 | **harry vault 안 단일 글로벌 위키**, in-place |
| D3 | librarian 에 dream/evolve | **포함** |
| D4 | librarian 자율성 | **티어드** — 안전건 자동 / 위험건 `_drafts/` promotion gate |
| D5 | 트리거/cadence | **월간** `schedule`/cron headless `claude -p "/wiki librarian"` + 수시 호출 (조정 가능) |

## 4. Vault 해석 (이름 기반, 머신 무관)

session-journal 과 동일 원리를 research-engine 에 **자체 포팅**(플러그인 간 의존 금지). 새 모듈 `lib/wiki/vault_resolve.mjs`.

해석 우선순위:
1. `WIKI_VAULT` — 명시적 절대경로(머신별 override).
2. `LLM_OBSIDIAN_VAULT_NAME` (+ `LLM_WIKI_SUBDIR`, 기본 `LLM-Wiki`) — OS별 `obsidian.json`(macOS `~/Library/Application Support/obsidian/obsidian.json`, Linux `~/.config/obsidian/obsidian.json`, Windows `%APPDATA%`)에서 vault 이름→로컬 경로 해석(open/최신 우선) 후 하위폴더 진입.
3. **하위호환 기본값**: `<cwd>/wiki` (기존 동작 유지 — 이름/경로 env 모두 없을 때).

`commands/wiki.md` 의 `VAULT=<project_cwd>/wiki` 상수를 `VAULT=$(node lib/wiki/vault_resolve.mjs)` 로 교체. `where` 류 진단(`node lib/wiki/vault_resolve.mjs --explain`)으로 해석 결과·모드 출력.

## 5. 폴더 레이아웃 + 태깅 + temporal

```
harry/LLM-Wiki/
├── AGENTS.md          # 헌법(§6 개정)
├── index.md           # 카탈로그(query 진입점, 재생성)
├── log.md             # ingest append-only (소스당 1줄)
├── change_log.md      # ★ librarian systems-memory (append-only; 마지막 run·적용·draft)
├── concepts/  entities/   # atemporal 정제 지식 (기존)
├── synthesis/         # ★ dream cross-cutting 페이지 (어떤 단일 소스도 명시 안 한 implicit connection)
├── ephemeral/         # ★ TTL/세션성 (optional; frontmatter expires) — 불변지식 오염 방지
├── _drafts/           # ★ promotion gate — 위험 산출 대기 (concepts/entities/synthesis 미러 구조)
├── _todos/            # ★ dream gap → 신규 리서치 질문 (research-engine /research 입력 후보)
└── _index/            # plan-*.json(기존), reflect_state.json(dream 증분), librarian_state.json, evolve-ledger.json
```

- **태깅**: 모든 생성 페이지 frontmatter 에 `tags: [ai-generated, llm-wiki, <type>]`(type ∈ concept|entity|synthesis|ephemeral). `index.md` 상단에 `🤖 AI-generated` 안내. 사용자는 `tag:#ai-generated` 로 검색·그래프 제외 가능(session-journal 과 일관).
- **temporal 분리(D 권고)**: `concepts/entities/synthesis` = atemporal(promotion·decay 정책 보수적), `ephemeral/` = `expires` 필드 있는 세션성(stale 정책 공격적). MVP 에선 ephemeral 은 **폴더만 마련**하고 ingest 는 기본 concepts/entities 유지, librarian 이 명백한 세션성(예: resolved bug, sprint 메모)만 ephemeral 후보로 draft.

## 6. AGENTS.md 헌법 개정 (`lib/wiki/AGENTS.template.md`)

기존 규칙 유지 + 추가:
- frontmatter 필수에 `tags` 추가(위 규칙). `updated` 는 librarian 도 갱신.
- 계층에 `synthesis/`(dream 전용, 반드시 2+ 소스 페이지 근거 명시), `ephemeral/`(expires), `_drafts/`(미승인 — query/publish 대상 제외) 설명 추가.
- **promotion 규칙**: 신규 페이지·새 related 링크·synthesis·evolve 산출은 `_drafts/` 에 먼저 쓴다. `promote` 통과 전에는 `index.md`/그래프에 안 올린다.
- **anti-AI writing** 짧은 스타일 가드(Wikipedia "Avoid AI-generated content" 요지) 한 단락 — 한국어 톤 유지.

## 7. 컴포넌트

### 7.1 ingest (기존, 재타게팅만)
`VAULT` 해석만 §4 로 바뀜. apply.mjs/frontmatter.mjs 에 `tags` 주입(아래 7.8). 그 외 단일-apply·중복 skip·perspective upsert 로직 불변.

### 7.2 query (기존, 불변)
index-first grep 합성. 단 `_drafts/`·`ephemeral/`(만료분) 제외. (읽기 전용 유지 — MVP 환류 없음.)

### 7.3 librarian ★ (신규) — `/wiki librarian [--report|--apply] [--budget N]`
**Stage 1 Audit(결정적, `lib/wiki/lint.mjs` 확장 → `librarian.mjs`)**: 기존 lint(unsourced/citation-unresolved/broken-link/orphan/duplicate-name) + 추가 stale(`updated` >90d) / raw-coverage(`log.md` 대비 미인제스트 research 세션) / provenance(sources 의 research 경로 실재).
**Stage 2 Tiered apply(D4)**:
- 🟢 자동: `#ai-generated` 태그 보정, `index.md`/`log.md`/`change_log.md` 갱신, broken-link 제거(어느 page related 에서 어떤 `[[slug]]` 제거인지 change_log 기록), 완전중복(slug/title 동일) merge, stale 플래그(`status: stale` 표시; 삭제 아님).
- 🟡 draft: 신규 페이지·새 cross-link 제안·dream synthesis·evolve 변경 → `_drafts/` + `outputs/librarian-<date>.md` 리포트.
**비용 가드**: `--budget` per-run 토큰/페이지 상한, 증분(마지막 run 이후 변경분 우선; `librarian_state.json`).

### 7.4 dream (wiki 모드) ★ — `/wiki dream` (research-engine `dream-extractor` 재사용)
위키 페이지 코퍼스를 입력으로 2단계: **discovery**(요약만으로 cross-cutting 테마·암묵 연결·모순·coverage gap 3~5 후보) → **synthesis**(증거 강한 것만 `synthesis/` **draft** 로, 근거 페이지 slug 인용). gap 은 `_todos/<topic>.md` 로 신규 리서치 질문 기록(이후 `/research` 입력). 증분 상태 `_index/reflect_state.json`. (InfraNodus gap-detection / Wang `/kb-reflect` 패턴과 동형.)

### 7.5 evolve (wiki 모드) ★ — `/wiki evolve` (research-engine `evolve` + prompt-mutator 재사용)
**evolvable region** = AGENTS.md 의 명시 구역(페이지 포맷/링크 규칙/태깅)·librarian 휴리스틱·페이지 템플릿. dream 산출 + lint 추세(반복되는 finding) 를 신호로 변형 후보 1~3개 생성 → `_drafts/_schema/` + `_index/evolve-ledger.json` 기록. **스키마 변경은 항상 draft**(promote 필요). research-engine evolve-ledger 컨벤션 차용.

### 7.6 promote ★ (신규) — `/wiki promote [<slug>|--all] [--critic]`
`_drafts/` 검토 → 승인분만 live(concepts/entities/synthesis/ephemeral) 이동 + `index.md`/`log.md`/`change_log.md` 갱신 + apply.mjs 멱등 반영. `--critic` 시 승격 전 소스(`research/<slug>`)대조 fact-check 서브에이전트 통과만 승격(confident-wrongness 2차 방어). 미승인 draft 는 보존(다음 run 재평가).

### 7.7 publish (기존, 불변)
Quartz + rsync. 단 content 복사에서 `_drafts/_todos/_index/ephemeral(만료)` 제외(공개 웹엔 검증분만).

### 7.8 공통 구현 포인트
- `frontmatter.mjs`: `tags` 직렬화/머지(기존 태그 보존 + 누락 보정).
- `apply.mjs`: write 경로를 `_drafts/` 로 분기하는 `--draft` 플래그.
- 모든 write op 자동 git commit(research-engine 기존 동작 유지 = audit trail).

## 8. 트리거 / cadence (D5)
- 기본 **월간**(주간 full-lint = 토큰 폭발, prior-art 다수 경고). 
- 메커니즘(권장): `schedule` 스킬 또는 cron → headless `claude -p "/wiki librarian --apply --budget <N>"` 매월 1일. 안전건 자동, draft 는 대기 → 사용자가 `/wiki promote` 로 처리.
- 수시: `/wiki librarian` `/wiki dream` `/wiki promote` 수동 호출 항상 가능.
- (대안: hetzner cron headless / Claude Scheduled Tasks — 운영 위치만 다름.)

## 9. 리스크 컨트롤 (prior-art 매핑)
| 위험 | 대응 |
|------|------|
| confident-wrongness | `_drafts/` promotion gate(D4) + `--critic` 소스 대조 |
| 토큰 폭발 / $/월 | 월간 + 증분 + `--budget` 캡 |
| second-brain graveyard | 안전건 자동화로 사용자 개입 최소 |
| temporal 오염 | concepts(불변) / ephemeral(TTL) 분리 |
| 추적 불능("누가 언제 왜") | wiki write 자동 commit + `change_log.md` |

## 10. 파일 변경 목록 (research-engine repo)
**신규**: `lib/wiki/vault_resolve.mjs`(+test), `lib/wiki/librarian.mjs`(+test), `commands/` 에 librarian/promote 액션(= `wiki.md` 확장 또는 분리), `docs/.../plans/2026-06-09-llm-wiki-librarian.md`.
**변경**: `commands/wiki.md`(VAULT 해석 §4, dream/evolve/librarian/promote 액션 추가), `lib/wiki/AGENTS.template.md`(§6), `lib/wiki/frontmatter.mjs`(tags), `lib/wiki/apply.mjs`(`--draft`), `lib/wiki/lint.mjs`(stale/coverage/provenance), `scripts/wiki_publish.sh`(draft/todos 제외), `commands/dream.md`·`evolve.md`(wiki 타깃 모드).
**불변**: query 핵심, slug.mjs, index_log.mjs(확장만).

## 11. 테스트 (bats/mjs)
- vault_resolve: 이름 해석/우선순위/폴백/미등록 vault.
- frontmatter tags 머지(기존 보존), apply `--draft` 경로 분기.
- librarian: stale/coverage/provenance 탐지; 티어드 — 안전건 적용 vs draft 격리 분리; budget 가드.
- promote: draft→live 멱등 이동 + index/log 갱신; `--critic` 거부 시 미승격.
- dream: synthesis draft + `_todos` 생성, reflect_state 증분.
- publish: `_drafts/_todos/ephemeral` 제외 검증.
- 회귀: 기존 ingest/query/lint 패스.

## 12. 비범위 (YAGNI)
- 임베딩/벡터 DB(카탈로그 직접판정 한계 전까지 보류 — 기존 spec 계승).
- query `--file` 환류(기존 spec out-of-scope 유지).
- Graphify/InfraNodus 그래프 레이어 연동(후속 — `_todos` gap 자동화 위에 얹을 수 있으나 MVP 아님).
- 완전 자동 promote(D4 가 명시 거부).

## 13. 미해결 / 후속
- ephemeral TTL 실제 만료/아카이브 정책(MVP 는 폴더+expires 만).
- critic 서브에이전트 모델 티어/비용.
- 멀티 vault(harry 외) 지원 — 현재 단일 글로벌만.
- session-journal 의 durable wiki 노트를 이 위키의 raw 소스로 흡수할지(별도 spec 후보 — "기존 데이터와 연결" 확장).
