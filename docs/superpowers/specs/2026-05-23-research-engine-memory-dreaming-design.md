---
title: research-engine — Memory & Dreaming (cross-session learning) 설계
slug: 2026-05-23-research-engine-memory-dreaming-design
created: 2026-05-23
status: draft (awaiting user review)
---

# research-engine — Memory & Dreaming

cross-session learning을 research-engine에 도입한다. 매 `/research` 세션이 독립적이라 *재발견 비용*이 누적되는 현 구조를, **누적 인덱스**(`research/_index/`) + **dream 인사이트 artifact**(`docs/dreams/`) + **세션 무결성 메타**(`content_sha256`, `created_by`)로 묶어 신규 세션이 *과거 세션과 dream 결과를 자동으로 prior_knowledge로 받게* 한다.

배경: Anthropic Claude Managed Agents의 *Memory*(파일시스템 + 스코프 + OCC + 감사로그)와 *Dreaming*(오프-밴드 자기개선)을 분석한 리서치(`research/2026-05-23-claude-managed-agents-memory-dreaming/`)에서 도출된 4개 이식 포인트를 research-engine의 실제 약점에 매핑한 단일 mega-spec.

## 1. 한 줄 요약

`/research`가 **자동으로 과거 유사 세션과 dream 인사이트를 어댑터 dispatch 프롬프트에 주입**하고, 5회 누적 시 `/dream`을 *제안*해 사용자가 명시 호출하면 **과거 세션들에서 반복 패턴·어댑터 실패·자주 묻는 의도를 추출해 readonly 인사이트로 누적**하는 자기 개선 루프를 만든다.

## 2. 목적

- **재발견 비용 제거**: 같은 토픽을 두 번째 리서치할 때 첫 번째 세션의 prior art / 어댑터 실패 / 의도 클러스터를 *수동 검색 없이* 자동 활용.
- **어댑터 자동 개선 경로**: `/bench`가 측정한 어댑터 약점(예: context7 quota, blog 404, github managed-agents 404)을 dream이 인사이트로 전환해 다음 /research가 *알고* 시작하도록.
- **세션 변조 감지·OCC 기반**: `cmux:cmux-orchestrator` 등 미래 multi-pane 사용 시 동시 followup·동시 수정 위험 차단.
- **Anthropic 설계 철학(파일시스템 = memory, 인간 편집 = adopt 결정)을 self-hosted 환경에 차용** — Dreaming API 직접 호출 없이 자체 LLM 호출(기존 Agent subagent dispatch 패턴 재사용)로 동일 효과.

## 3. 스코프

### In-scope
- 신규 디렉토리 `research/_index/` (manifest + dream-ledger)
- 신규 디렉토리 `docs/dreams/<run-id>/` (readonly 인사이트 artifact)
- 신규 스크립트 `scripts/memory_reindex.sh`, `scripts/memory_query.sh`, `scripts/dream_run.sh`
- 신규 슬래시 `commands/dream.md` + 신규 에이전트 페르소나 `agents/dream-extractor.md`
- 기존 `commands/research.md` Stage 2, 5.2, 5.8 hook 3 곳
- 기존 `commands/bench.md` post-hook 1 곳 (제안만)
- 기존 `commands/research-followup.md` OCC precondition 1 곳
- 신규 vitest unit (`lib/memory/*.test.mjs`) + bats integration / e2e

### Out-of-scope (이번 spec에서 다루지 않음)
- 기존 80여 세션 파일 백필 — manifest에서 derived로만 인식, 원본 파일 무변경
- 임베딩 기반 유사도 (가중합 휴리스틱으로 시작)
- Notion 동기화 확장 (dream artifact의 Notion push는 followup spec)
- 자동 머지 / Anthropic Dreaming API 직접 호출 — 인간 편집 = adopt 결정 모델 유지
- multi-user / 공유 memory store — 현 시점 로컬 single-user 가정

## 4. 데이터 모델

### 4.1 `research/_index/manifest.json` (readonly 누적 인덱스, derivable)

```json
{
  "version": 1,
  "generated_at": "<ISO8601>",
  "generator": "scripts/memory_reindex.sh@<git-sha>",
  "sessions": [
    {
      "slug": "2026-05-23-claude-managed-agents-memory-dreaming",
      "path": "research/2026-05-23-claude-managed-agents-memory-dreaming",
      "input_type": "youtube",
      "input": "https://youtu.be/...",
      "title": "...",
      "created": "<ISO8601>",
      "intent": {
        "purpose": "...",
        "focus": "...",
        "audience_level": "...",
        "purpose_tokens": ["memory", "dreaming", "..."]
      },
      "sources_summary": { "count": 22, "by_type": { "arxiv-paper": 7, "github-repo": 8, "...": "..." } },
      "topics": ["agent memory", "self-improvement", "..."],
      "related_count": 18,
      "content_sha256": "<README.md sha256>",
      "created_by": [
        { "actor_type": "adapter", "id": "youtube-adapter" },
        { "actor_type": "adapter", "id": "github-adapter" }
      ],
      "notion_url": "https://www.notion.so/...",
      "dreamed_in": ["drm_2026-06-01-..."]
    }
  ],
  "dreams": [
    {
      "run_id": "drm_2026-06-01-managed-agents-memory",
      "path": "docs/dreams/drm_2026-06-01-managed-agents-memory",
      "created": "<ISO8601>",
      "status": "active",
      "supersedes": null,
      "inputs": ["2026-05-23-...", "..."],
      "insight_files": ["pattern-adapter-failure-modes.md", "..."]
    }
  ]
}
```

`purpose_tokens`: intent.purpose를 NFC 정규화 + 한·영 토크나이즈한 키워드 배열 (preview 유사도 검색용).
`content_sha256`: 세션 `README.md`의 sha256 — `/research-followup` OCC precondition.

### 4.2 `research/_index/dream-ledger.json` (5회 누적 제안 트리거)

```json
{
  "version": 1,
  "last_dream_run_id": "drm_2026-06-01-managed-agents-memory",
  "last_dream_at": "<ISO8601>",
  "sessions_since_last_dream": ["2026-05-23-...", "..."],
  "suggestion_threshold": 5,
  "suggestion_shown_at": null,
  "last_shown_count": 0
}
```

`last_dream_run_id`가 `null`이면 *모든 누적 세션*을 since로 본다.
`suggestion_threshold=5`는 사용자가 ledger를 직접 편집해 변경 가능.

### 4.3 `docs/dreams/<run-id>/` 레이아웃

```
docs/dreams/drm_2026-06-01-managed-agents-memory/
├── README.md           ← 통합 인사이트 (사람이 읽고 편집 = adopt 결정)
├── sources.json        ← 입력 세션 슬러그 + 각 세션 README.md의 sha256 fingerprint
├── insights/
│   ├── pattern-adapter-failure-modes.md
│   ├── pattern-recurring-intents.md
│   ├── pattern-prior-art-clusters.md
│   └── pattern-topic-coverage-gaps.md
└── meta.json           ← {model, prompt_version, cost_tokens?, input_count, generated_at}
```

`README.md` frontmatter:
```yaml
---
run_id: "drm_2026-06-01-managed-agents-memory"
created: "<ISO8601>"
inputs: ["...", "..."]
status: "active"     # active | superseded | discarded
supersedes: null     # 또는 이전 run_id
---
```

`status=discarded` → `memory_query.sh`가 이 dream을 prior_knowledge에서 제외 (= 사용자의 *adopt 거부* 의사).
`status=superseded` → 동일 또는 더 작은 입력 세트로 더 새 dream이 돌았을 때 자동 표시.

### 4.4 신규 `research/<slug>/sources.json`에 추가될 두 필드

```json
{
  "...existing...": "...",
  "content_sha256": "<README.md hash>",
  "created_by": [
    { "actor_type": "adapter", "id": "youtube-adapter", "model": "claude-opus-4-7", "ts": "<ISO8601>" },
    { "actor_type": "adapter", "id": "github-adapter", "model": "claude-opus-4-7", "ts": "<ISO8601>" }
  ]
}
```

기존 80여 세션은 이 필드가 없음 → manifest indexer가 *읽을 때 derived로* 채움. 신규 세션은 `/research` Stage 5.2에서 명시 기록.

### 4.5 메타데이터 책임 매트릭스

| 위치 | 필드 | 누가 채움 | 언제 |
|---|---|---|---|
| `research/<slug>/sources.json` | `content_sha256`, `created_by[]` | `/research` Stage 5.2 | 신규 세션 작성 시 |
| `research/_index/manifest.json` | 전체 | `memory_reindex.sh` | reindex 시 (idempotent) |
| `research/_index/dream-ledger.json` | `sessions_since_last_dream`, `suggestion_shown_at`, `last_shown_count` | `/research` Stage 5.8 | 매 /research 종료 |
| `research/_index/dream-ledger.json` | `last_dream_run_id`, `last_dream_at`, `sessions_since_last_dream=[]`, `suggestion_shown_at=null`, `last_shown_count=0` | `/dream` 종료 시 (D6) | dream run 완료 |
| `docs/dreams/<run-id>/*` | 전체 | `/dream` (= `dream_run.sh`) | dream 실행 시 |

## 5. 데이터 흐름

### 5.1 `/research` 시퀀스 (memory 자동 주입)

```
[Stage 1] classify_url.sh                                          (변경 없음)
[Stage 2] preview
   └─ NEW: memory_query.sh
        1. read _index/manifest.json
        2. similarity match: input_type 동치(3) + topics 교집합(2) + purpose_tokens(1) 가중합
        3. top-K(default 5) sessions
        4. + active dream insights (status=active만)
        5. write cache/memory.json
[Stage 3] intent Q&A                                               (변경 없음)
[Stage 4] parallel dispatch
   └─ NEW: 각 adapter prompt에 prior_knowledge 섹션 주입
           guidance: "Treat prior_knowledge as hints, not facts. Cite if you reuse a finding."
[Stage 5] synthesize + persist
   ├─ 5.2: sources.json에 content_sha256 + created_by 기록             ← NEW
   ├─ 5.7: push_to_notion                                            (변경 없음)
   ├─ END: memory_reindex.sh 자동 호출 (idempotent)                   ← NEW
   └─ 5.8: dream-ledger update + suggestion check                    ← NEW
        - count >= threshold && suggestion_shown_at is None → 제안 1줄
        - 또는 count >= last_shown_count + threshold → 제안 1줄
```

**핵심 결정**: `cache/memory.json`은 어댑터 공통 입력. dispatcher가 한 번 만들어 모든 어댑터 dispatch JSON의 `prior_knowledge` 키에 동일 사본 첨부 — fetch 중복 없음.

### 5.2 `/dream` 시퀀스 (Dreaming 패턴)

```
사용자: /dream                                  (default: last_dream 이후 누적 전체)
       또는 /dream --since=14d
       또는 /dream --slugs=a,b,c
       또는 /dream --bench=<bench-run-id>     (bench 결과를 입력에 합침)

[D1] resolve inputs
     - load dream-ledger.json
     - apply 인자
     - sanity: ≥2 sessions? else error "not enough sessions"
[D2] mint run_id = drm_<YYYY-MM-DD-HHMM>-<top-topic-slug>
     mkdir docs/dreams/<run-id>/{insights,}
     write meta.json (model, prompt_version, input_count, ...)
[D3] dispatch dream-extractor agent (Agent subagent, 기존 어댑터와 동일 패턴)
     inputs: { run_id, session_paths, manifest_excerpt, intent_distribution, bench_excerpt? }
     agent emits JSON: { patterns: [...], failures: [...], recurring_intents: [...] }
[D4] split into insights/ files by category
     - pattern-adapter-failure-modes.md
     - pattern-recurring-intents.md
     - pattern-prior-art-clusters.md
     - pattern-topic-coverage-gaps.md
[D5] write docs/dreams/<run-id>/README.md
     - frontmatter: status="active", supersedes=<prev or null>
     - 통합 인사이트 본문 (Top N 패턴 + 액션 권고)
     - sources.json: 입력 슬러그 + 각 sha256
[D6] update _index/dream-ledger.json
     - last_dream_run_id = run_id
     - last_dream_at = now
     - sessions_since_last_dream = []
     - suggestion_shown_at = null
     - last_shown_count = 0
[D7] memory_reindex.sh 호출 (manifest에 dream 추가, sessions[].dreamed_in 업데이트)
[D8] final message
     "📄 docs/dreams/<run-id>/README.md
      2줄 TL;DR
      N개 insight 파일 — 부적절한 것은 status=discarded로 표시"
```

### 5.3 `/bench` post-hook (제안만)

`/bench` 종료 시:
```
if dream-ledger.last_dream_at < bench.started_at:
    print "💡 새 bench 결과: /dream --bench=<bench-run-id> 로 어댑터 약점을 인사이트로 전환 가능"
```
자동 트리거 없음 — 모든 dream 트리거는 *제안만, 실행은 사용자*.

### 5.4 reindex 호출 시점 3개

`memory_reindex.sh`는 idempotent. 트리거:
1. **명시적**: 사용자 직접 호출 (manifest 손상 복구).
2. **/research Stage 5 끝**: 신규 세션 즉시 반영 — 다음 /research가 자기 자신을 prior로 보지 않게.
3. **/dream D7**: dreamed_in 업데이트 + 새 dream artifact 포함.

세 경로 모두 같은 스크립트 호출.

## 6. 컴포넌트 인벤토리

### 6.1 신규 파일

| 파일 | 역할 |
|---|---|
| `commands/dream.md` | 슬래시 `/dream` 진입 — D1~D8 시퀀스 명세 |
| `agents/dream-extractor.md` | dream agent persona (기존 어댑터 페르소나 패턴 차용) |
| `scripts/memory_reindex.sh` | manifest + ledger 재생성 (idempotent, atomic rename) |
| `scripts/memory_query.sh` | manifest 읽고 top-K prior + active dreams 반환 (fail-soft, exit 0) |
| `scripts/dream_run.sh` | D1·D2·D4~D7 파일 IO 책임 (입력 resolve, run-id mint, 디렉토리 생성, insights split, README/sources/meta 작성, ledger·manifest 갱신). D3 Agent dispatch는 `commands/dream.md` 슬래시 시퀀스가 Claude로 하여금 Agent tool을 호출하게 함 — dream_run.sh는 그 결과 JSON을 stdin/파일로 전달받아 D4부터 이어받는다. |
| `lib/memory/manifest_schema.mjs` | manifest JSON 스키마 + 빌드 유틸 |
| `lib/memory/similarity.mjs` | 가중합 유사도 함수 |
| `lib/memory/ledger.mjs` | 카운터 상태기계 |
| `lib/memory/tokenize.mjs` | intent.purpose 한·영 토크나이즈 |
| `tests/research-engine/memory.test.sh` | bats integration (reindex / query) |
| `tests/research-engine/dream.test.sh` | bats integration (인자 처리) |
| `tests/research-engine/research-with-memory.test.sh` | bats e2e (prior 주입) |
| `tests/research-engine/dream-e2e.test.sh` | bats e2e (풀 사이클 + status 편집) |
| `lib/memory/*.test.mjs` | vitest unit (스키마 / 유사도 / 토크나이저 / 카운터) |

### 6.2 기존 파일 수정

| 파일 | 변경 |
|---|---|
| `commands/research.md` | Stage 2/5.2/5.8에 hook 3곳 |
| `commands/research-followup.md` | session.md write 직전 sha256 precondition 1곳 |
| `commands/bench.md` | post-hook 제안 1줄 |
| `package.json` | `test:bats`에 새 bats 파일들 추가 |

### 6.3 git ignore vs commit

- `research/_index/manifest.json` — **commit**. 재생성 가능하지만 다른 협업자/머신이 즉시 prior를 받게 하려면 트래킹이 더 유용. 충돌 시 `bash scripts/memory_reindex.sh` 한 줄로 해결.
- `research/_index/dream-ledger.json` — **commit**. 카운터·last_dream 상태는 history에 남는 게 유용.
- `docs/dreams/<run-id>/` — **commit**. *사람이 읽는 인사이트 문서*이고 사용자 편집(status 변경)이 의미 있음.

## 7. 에러 처리 & 경계 케이스

### 7.1 manifest.json 손상/손실
- `memory_query.sh`: fail-soft. 빈 prior 반환 + stderr 한 줄 + `/research` 진행.
- `memory_reindex.sh`: 항상 처음부터 재생성 (입력 = `research/*/sources.json` + `docs/dreams/*/README.md`).
- `/dream`: fail-fast. 명시 에러 + reindex 안내.
- *원칙: 읽기 경로는 fail-soft, 쓰기 경로는 fail-fast.*

### 7.2 dream-ledger.json 손상/손실
자동 재생성: `last_dream_run_id`는 가장 최근 active dream에서, `sessions_since_last_dream`은 manifest에서 *그 dream 이후 created된 세션들*로 산출. `suggestion_shown_at=null` 리셋. stderr 한 줄, 진행 계속.

### 7.3 OCC sha256 mismatch (`/research-followup`)
1. read: 현재 session.md sha256 → expected
2. content 생성 (LLM 호출)
3. write 직전: 재계산 → actual
4. mismatch → 1회 자동 재시도 (Stage 2 재실행)
5. 2회 연속 mismatch → 사용자 알림 + 수동 머지 안내

### 7.4 dream-extractor agent 실패
- **JSON 파싱 실패**: 1회 자동 재시도 + 엄격한 prompt. 2번째 실패 → `FAILED.md` 만 남기고 종료, ledger 미업데이트 (다음 dream 재시도 가능).
- **빈 patterns**: 정상 완료, README.md에 "no significant patterns" 노트, ledger 업데이트.
- **타임아웃 5분 초과**: 파싱 실패와 동일 처리.

### 7.5 5회 누적 제안 반복 방지
```python
if last_dream_at is None:
    count = len(all sessions ever)
else:
    count = len(sessions_since_last_dream)

if count >= threshold and suggestion_shown_at is None:
    print 제안; suggestion_shown_at = now; last_shown_count = count
elif count >= last_shown_count + threshold:
    print 제안; suggestion_shown_at = now; last_shown_count = count
```
→ 5, 10, 15...에서만. 그 사이 6~9는 트리거 안 함.

### 7.6 사용자 dream README 편집 동기화
- `status: active → discarded` 편집 → 다음 `memory_query.sh`가 그 dream을 prior에서 제외.
- 디렉토리 삭제 → reindex로 manifest 동기화.
- 본문 수정 → 그대로 prior_knowledge에 들어감 (사용자 의도 보존).

### 7.7 reindex 동시 실행
- 임시 파일 + atomic rename (`manifest.json.tmp` → `manifest.json`).
- 두 reindex 동시 → 늦은 rename이 이김. idempotent이므로 손실 없음. lock 불필요.

## 8. 테스트 전략

### 8.1 레이어 매트릭스

| 레이어 | 도구 | 대상 | 위치 |
|---|---|---|---|
| Unit | `vitest` | manifest 스키마, 유사도 매처, ledger 상태기계, 토크나이저 | `lib/memory/*.test.mjs` |
| Shell integration | `bats` | reindex / query / dream_run 입출력 계약 | `tests/research-engine/memory.test.sh`, `dream.test.sh` |
| E2E | `bats` + mock claude CLI | prior_knowledge 주입, dream 풀 사이클 | `tests/research-engine/research-with-memory.test.sh`, `dream-e2e.test.sh` |

### 8.2 핵심 invariants (테스트가 보장)

1. **Idempotency**: `memory_reindex.sh` 2회 = 1회와 byte-identical.
2. **Read-only on legacy**: 기존 세션 파일 mtime이 reindex 후에도 불변 (`stat -c %Y` 검증).
3. **Self-exclusion**: 세션 X에 대한 `memory_query`는 X를 prior에 반환하지 않음.
4. **Fail-soft on read**: manifest 부재가 `/research`를 막지 않음 (exit 0).
5. **Fail-fast on write**: `/dream`은 manifest 부재 시 명시 에러 (exit non-zero).
6. **Atomic manifest swap**: 부분 쓰여진 manifest를 읽을 수 없음 (rename 원자성 + 임시 파일 사용).
7. **Discarded 제외**: dream status=discarded면 `memory_query`가 prior_knowledge에서 제외.
8. **OCC mismatch 자동 재시도**: 1회 자동, 2회는 사용자에게 알림.

### 8.3 E2E 시나리오

- **research-with-memory**: fixture 3개 세션 + reindex → `/research <new-similar-url>` → cache/memory.json에 3개 prior 확인 + dispatch prompt에 prior_knowledge 섹션 확인.
- **dream-e2e**: fixture 5개 세션 + 빈 ledger → 추가 `/research` 1회 (카운터 6) → final message 제안 줄 확인 → `/dream` 호출 → docs/dreams/<run-id>/README.md 생성 + ledger 초기화 + manifest dreamed_in 업데이트 → status=active → discarded 수동 편집 → 다음 `/research` 호출 시 query가 그 dream 제외 확인.

## 9. 미해결 / Future work

- **임베딩 유사도**: 가중합이 1000+ 세션에서 의미 미스 시 v2에서 임베딩 인덱스(e.g., chroma) 도입 — 본 spec은 시간 기준으로 가중합 휴리스틱만.
- **dream artifact의 Notion 미러**: 현재 spec은 로컬만. push_to_notion.sh를 dream에도 적용할지는 followup spec.
- **/dream-pin / /dream-unpin**: 특정 insight 고정·숨김 명령은 도입하지 않음. 사용자 편집(status field, 파일 삭제)으로 충분하다고 판단.
- **자동 머지 (auto-adopt) 정책**: 추가 안 함. 모든 채택은 사용자가 markdown을 *그대로 두는 것*으로 표시.
- **Anthropic Dreaming API 직접 호출**: 향후 Research Preview → GA 시 raw `POST /v1/dreams` 옵션을 dream_run.sh에 *대안 백엔드*로 추가 가능. 본 spec은 자체 Agent dispatch만.

## 10. Acceptance criteria

- `/research` 1회 실행이 cache/memory.json을 생성하고 어댑터 dispatch JSON에 `prior_knowledge`가 포함된다 (bats e2e로 검증).
- 신규 세션의 `sources.json`에 `content_sha256` + `created_by`가 비어있지 않다.
- `bash scripts/memory_reindex.sh` 두 번 연속 실행 결과가 byte-identical (`diff` 통과).
- 누적 5회 째 `/research` 종료 메시지에 `/dream` 제안 한 줄이 포함되어 있다.
- `/dream` 한 번이 `docs/dreams/<run-id>/` 디렉토리와 ≥1개 insight 파일을 생성하고, dream-ledger의 카운터를 0으로 리셋한다.
- dream README의 `status: active → discarded` 변경 후 다음 `memory_query.sh` 호출이 그 dream을 prior에 포함하지 않는다.
- 기존 80여 세션의 파일 mtime이 reindex 전후로 불변이다.
- `/research-followup`이 동시 실행 시 (수동 시뮬레이션) sha256 mismatch에 1회 자동 재시도한다.
