---
title: research-engine — /research-design 분리 → /spec, /design, /deploy 3개 스킬 설계
slug: 2026-05-23-research-engine-pipeline-split-design
created: 2026-05-23
status: draft (awaiting user review)
---

# `/research-design` 분리 — `/spec`, `/design`, `/deploy` 세 스킬로 분해

## 1. 한 줄 요약

현재 design + 개발 + 배포가 한 파이프라인에 묶인 `/research-design` 을 책임 단위로 분리한다. 이번 작업 범위는 **`/spec` (신규) · `/design` (재정의) · `/deploy` (신규)** 3개. 사용자 수동 `build` 단계가 중간에 끼고, orchestrator (`/ship`) 와 자동화된 `/build` 는 이번 spec 에서 다루지 않는다.

## 2. 목적

- 기존 `/research-design` 의 `--no-deploy` 플래그 자체가 design 과 deploy 가 분리되어야 한다는 신호. 책임이 섞여 있어 디버깅·재실행·도구 교체가 어려움.
- 사용자가 design 후 외부 툴 (v0, cursor, 직접 코딩 등) 로 build 를 진행한 뒤 deploy 만 자동화하길 원함 → build 단계 빠진 채로 양 끝단이 깔끔한 파이프라인 필요.
- 각 스킬은 단일 책임, 파일 contract 만으로 다음 단계와 통신. 어떤 stage 든 독립 실행·재실행 가능.

## 3. 입출력

**입력**
- `/spec <slug>` — `research/<slug>/README.md`, `intent.json`
- `/design <slug>` — `research/<slug>/README.md`, `spec/spec.md`
- `/deploy <slug>` — `research/<slug>/app/`, `spec/scenarios.json`, `design/handoff/` (참고)

**출력**

```
research/<slug>/
├── README.md / sources.json / intent.json / cache/ / related/    # /research (기존)
│
├── spec/                           # /spec
│   ├── scenarios.json              #   TDD e2e 계약. /deploy 의 G3 입력
│   ├── spec.md                     #   사람 읽는 contract 요약
│   └── runs/<ISO>/log.jsonl
│
├── design/                         # /design
│   ├── handoff/                    #   claude.ai/design raw export
│   │   ├── index.html / assets/ / meta.json
│   └── runs/<ISO>/
│       ├── collect.log / screenshots/ / log.jsonl
│
├── app/                            # USER MANUAL — 외부 툴로 빌드한 Next.js 등
│   ├── package.json / src/ / ...
│   └── .deploy-hints.json          # optional override (없으면 /deploy 가 package.json 에서 auto-detect)
│
└── deploy/                         # /deploy
    ├── deploy.json                 # {target, host, lxc_id, deployed_at, prev_host?, g3}
    └── runs/<ISO>/
        ├── adapter.log / gate-3.json / log.jsonl
```

## 4. 성공 기준 (게이트)

| Gate | 위치 | 통과 조건 |
|---|---|---|
| **G0: spec quality** | `/spec` 종료 시 | `ajv` schema strict PASS + scenarios ≥ 3개 + 모든 scenario 가 `expectNoConsoleError` 또는 `expect.*` step 최소 1개 |
| **G3: production** | `/deploy` 직후 | prod URL 대상 Playwright PASS (scenarios.json 의 `baseUrl.prod` 사용) + `GET /health` 200 |

G1·G2 (build 게이트) 는 이번 scope 밖. 각 게이트 결과는 해당 stage 의 `runs/<ISO>/gate-{0,3}.json` 으로 보존.

## 5. 아키텍처

### 5.1 모듈 책임

**신규/변경 슬래시 커맨드**

| Command | 역할 |
|---|---|
| `/research` (기존, 변경 없음) | 주제·URL → README + intent |
| `/spec <slug>` (신규) | TDD 계약 생성. README + intent → scenarios.json + spec.md |
| `/design <slug>` (`/research-design` 재정의·rename) | claude.ai/design 핸드오프 only. handoff bundle 다운로드까지만 |
| `/deploy <slug>` (신규) | `app/` 를 hetzner LXC 에 배포. G3 e2e 실행 |

**신규 agents**
- `agents/spec-author.md` — README + intent 에서 user flow 추출 → playwright 스텝 변환 → scenarios.json
- `agents/deploy-planner.md` — `app/` 분석 (package.json, deps) → LXC 사양 결정. `hetzner-master` repo 의 LXC template convention 준수

**신규 scripts**
```
scripts/
  spec_generate.sh           # /spec 본체. spec-author agent 디스패치 + ajv 검증
  design_collect_only.sh     # /design 본체. 기존 design_collect.mjs 의 thin wrapper
  deploy_dispatch.sh         # /deploy 본체. --target=lxc (default) 분기
  deploy_lxc.sh              # 기존 scripts/lxc_deploy.sh 이동·rename. hetzner-master 참조
```

**Adapter 구조 (deploy)** — 이번 작업은 LXC 만 실구현. `deploy_dispatch.sh` 가 단순 분기로 향후 cloudflare·vercel 어댑터 추가 여지만 남김. 추상화 인터페이스는 만들지 않음 (YAGNI).

**유지·재사용 (그대로)**
- 어댑터 15개 (`youtube-adapter`, `arxiv-adapter`, ...) — `/research` 가 사용
- `design_collect.mjs`, `cloak_login.mjs`, `manual_login.mjs` — `/design` 이 재사용
- `design-builder`, `design-critic`, `design-merger` agents — 손대지 않음 (이번 작업에서 미사용, 향후 `/build` 자리)

**제거·deprecate**
- `commands/research-design.md` → `commands/design.md` 로 rename·rewrite (scope 축소)
- `scripts/research_design_pipeline.sh` → 삭제
- `scripts/lxc_deploy.sh` → `scripts/deploy_lxc.sh` 로 이동·rename

### 5.2 데이터 흐름

```
/research <URL>
  → research/<slug>/README.md + sources.json + intent.json
  ▼
/spec <slug>
  → spec-author agent (LLM) 디스패치, README+intent 컨텍스트 주입
  → scenarios.json 생성 → ajv strict validate → G0
  → spec/scenarios.json, spec/spec.md, spec/runs/<ISO>/log.jsonl
  ▼
/design <slug>
  → storageState → cloak-browser → manual_login (Tailscale m4) 폴백
  → claude.ai/design 진입, README + spec.md 첨부 (spec.md 가 user flow·contract 를 design 에 가이드)
  → 프롬프트 전송
  → "Hand off" 클릭 → handoff bundle 다운로드
  → design/handoff/, design/runs/<ISO>/{collect.log,screenshots,log.jsonl}
  ▼
[사용자 수동] — 외부 툴로 handoff → Next.js 코드 변환
  → research/<slug>/app/ 채움 (package.json + src/ + ...)
  → 선택사항: .deploy-hints.json 작성 (override)
  ▼
/deploy <slug>
  → deploy-planner agent: app/package.json 읽어 runtime/build/start 자동 추론
  → .deploy-hints.json 있으면 override
  → deploy_lxc.sh: hetzner-master template convention 으로 LXC 생성·갱신
  → Tailscale hostname 등록 → Caddy + systemd 셋업 → Next.js prod start
  → scenarios.json 의 baseUrl.prod 로 e2e + /health → G3
  → deploy/deploy.json, deploy/runs/<ISO>/{adapter.log,gate-3.json,log.jsonl}
```

각 stage 는 자기 디렉터리만 쓰고, 다음 stage 의 입력은 그 디렉터리의 contract 파일 (`scenarios.json`, `handoff/meta.json`, `app/package.json`).

### 5.3 인터페이스 계약

**`scenarios.json` (spec → deploy)** — 기존 `tests/research-design/schemas/scenarios.schema.json` 그대로 사용. 위치만 `tests/research-engine/schemas/` 로 이동. 추가 필드:

```json
{
  "...": "...",
  "_meta": {
    "generated_by": "spec-author@<git-sha>",
    "generated_at": "<ISO>",
    "source_intent_hash": "<sha256 of intent.json>"
  }
}
```
`source_intent_hash` 가 현재 `intent.json` 의 sha256 과 다르면 spec stale — `/design` 과 `/deploy` 시작 시 stderr 경고 1줄 출력 후 진행. 자동 재실행 안 함 (사용자가 명시적으로 `/spec` 재실행 결정).

**`handoff/meta.json` (design → 사용자/deploy 참고)** — 변경 없음. 기존 `lib/design_handoff_parser.mjs` 호환.

**`.deploy-hints.json` (사용자 → deploy, optional)**:
```json
{
  "runtime": "node@22",
  "package_manager": "pnpm",
  "build_cmd": "pnpm build",
  "start_cmd": "pnpm start",
  "port": 3000,
  "env_keys": ["DATABASE_URL"],
  "static_only": false,
  "estimated_ram_mb": 256
}
```
파일 없으면 deploy-planner agent 가 `app/package.json` 의 `scripts.build`, `scripts.start`, `engines.node`, 의존성 목록에서 추론. Next.js (primary 타깃) 는 추론 안정적, 기타 Node 프레임워크 (vite, remix 등) 는 `.deploy-hints.json` 권장. 정적 사이트 (static_only: true) 는 build 단계 skip 하고 Caddy 가 직접 서빙. 추론 실패 시 G3 전에 명확한 한글 에러로 stop.

**`deploy.json` (deploy → 사용자)**:
```json
{
  "target": "lxc",
  "host": "<slug>.<tailnet>.ts.net",
  "lxc_id": 142,
  "deployed_at": "<ISO>",
  "prev_host": "<slug>.<tailnet>.ts.net",
  "g3": { "passed": true, "report": "runs/<ISO>/gate-3.json" }
}
```

## 6. 게이트 & 실패 정책

### Stage 별 실패 처리

| Stage | 실패 종류 | 처리 |
|---|---|---|
| `/spec` | LLM 출력이 schema invalid | 1회 재시도 (validation error 를 system prompt 에 inject) → 또 실패시 exit 1, partial output 보존 |
| `/spec` | scenarios < 3개 | exit 1, 사용자에게 수동 보강 안내 |
| `/design` | storageState 만료/cloak 실패 | manual_login (Tailscale m4 Chrome) fallback |
| `/design` | claude.ai/design 셀렉터 변경 | 1회 재시도 → screenshot+console+network 덤프 → exit 1 |
| `/deploy` | `app/` 미존재 또는 `package.json` 없음 | exit 1, "사용자 build 필요" 한글 안내 |
| `/deploy` | deploy-planner 추론 실패 | exit 1, 사용자에게 `.deploy-hints.json` 작성 안내 |
| `/deploy` | hetzner-master template 조회 실패 | exit 4, app/ 보존, 수동 절차 안내 |
| `/deploy` | LXC 생성·배포 실패 | exit 4. 이전 컨테이너 (`deploy.json.prev_host`) 가 있으면 active 유지 (롤백 없음 — 신규만 실패) |
| `/deploy` | G3 실패 | 이전 컨테이너로 자동 롤백 (Tailscale hostname swap) → 신규 컨테이너 destroy → exit 4 |

**원칙**: 재시도는 stage 당 최대 1회. 가려진 실패 원인 방지.

### 로깅 표준

모든 stage 의 `runs/<ISO>/log.jsonl` 공통 schema:
```json
{"ts": "<ISO>", "stage": "deploy", "step": "g3.ok", "msg": "host=<host>", "extra": {...}}
```

## 7. 마이그레이션

- 기존 `commands/research-design.md` → `commands/design.md` rename·rewrite. `/research-design` 슬래시 사라짐.
- 기존 `scripts/research_design_pipeline.sh` 삭제.
- 기존 `scripts/lxc_deploy.sh` → `scripts/deploy_lxc.sh` 이동·rename.
- 기존 `tests/research-design/` 의 `schemas/scenarios.schema.json` → `tests/research-engine/schemas/` 이동. 그 외 `tests/research-design/` 콘텐츠 (e2e, fixtures, judge_fixture.json, pipeline.test.sh, mock-bin) 는 이번 작업에서 손대지 않음 (향후 `/build` 도입 시 통합).
- 시드 슬러그 `2026-05-22-ai-image-vectorization-service` 의 `design/handoff/` 는 보존 — `/design` 의 stamp 로 인식되어 재실행 시 skip.

## 8. TDD 테스트 계획

### 8.1 Red-first commit 순서

모든 RED 커밋이 본 구현 한 줄 전에 main 에 들어간다.

| Commit | 내용 | 상태 |
|---|---|---|
| 1 | `tests/research-engine/schemas/scenarios.schema.json` (기존 위치에서 이동) + `lib/scenarios_validator.mjs` 의 인터페이스 stub + `lib/scenarios_validator.test.mjs` (3 fixture: valid / missing-field / extra-meta) | RED — validator 미구현 |
| 2 | `tests/research-engine/spec.test.sh` — `/spec <slug>` mock 호출 → G0 통과 검증. LLM 출력은 fixture 파일로 stub | RED — /spec 미구현 |
| 3 | `tests/research-engine/design.test.sh` — `tests/research-engine/fixtures/handoff-sample/` 에 캡처된 handoff fixture 두고, `/design` 이 cache mode 로 fixture 인식 검증 | RED — /design 의 cache mode 미구현 |
| 4 | `tests/research-engine/deploy.test.sh` — LXC adapter stub (실제 hetzner 호출 안 하고 mock host 반환) + scenarios.json 의 prod baseUrl 로 G3 e2e 실행 시도 검증. mock app 은 `python -m http.server` 로 띄움 | RED — /deploy 미구현 |
| 5 | `scripts/spec_generate.sh`, `scripts/design_collect_only.sh`, `scripts/deploy_dispatch.sh` skeleton (모두 exit 1 + "not implemented") | RED 유지 — skeleton 만 |

### 8.2 GREEN 화 순서

1. `lib/scenarios_validator.mjs` GREEN
2. `agents/spec-author.md` + `scripts/spec_generate.sh` GREEN → `/spec` 사용 가능
3. `scripts/design_collect_only.sh` + `commands/design.md` (기존 `design_collect.mjs` 재사용) GREEN → `/design` 사용 가능
4. `agents/deploy-planner.md` + `scripts/deploy_lxc.sh` (기존 lxc_deploy.sh 이동) + `scripts/deploy_dispatch.sh` + `commands/deploy.md` GREEN → `/deploy` 사용 가능
5. End-to-end manual 검증: `/research <URL>` → `/spec <slug>` → `/design <slug>` → [사용자 수동 build, `app/` 채움] → `/deploy <slug>` → live URL

## 9. 외부 의존성

- 신규: `hetzner-master` GitHub repo — LXC template convention 조회용 read-only. git clone 으로 캐시 (`~/.cache/research-engine/hetzner-master/`)
- 신규: `ajv` (npm) — `scenarios_validator.mjs`
- 변경 없음: playwright, cloak-browser, herdr, claude/codex CLI, hetzner-proxmox-deploy 스킬, Tailscale, Notion
- 제거 없음

## 10. YAGNI — 의도적으로 안 하는 것

- `/build` 자동화 — 사용자 수동. 향후 별도 spec
- `/ship` orchestrator — `/build` 도입 시 같이
- Cloudflare Tunnel · Vercel · public DNS — LXC + Tailscale internal 만. 어댑터 추상 인터페이스도 만들지 않음
- 다중 슬러그 동시 처리
- `app/` 위치를 사용자 정의 가능하게 만들기 — `research/<slug>/app/` 하드코딩. `--app <path>` 옵션도 추가 안 함
- 향후 `/build` 도입을 고려한 사전 슬롯 (사용자 결정)
- spec 의 cascade invalidation 자동화 — `source_intent_hash` mismatch 는 경고만, 자동 재실행 안 함
- G3 e2e 의 cross-browser — desktop chromium 만

## 11. 본 spec 의 추정 / 사용자 review 에서 확정해야 할 값

| 항목 | 본 spec 의 가정값 | 검토 포인트 |
|---|---|---|
| `hetzner-master` repo 경로 | `gprecious/hetzner-master` | 다른 repo? 접근 토큰 채널? |
| spec-author LLM 모델 | claude haiku (cost) | sonnet/opus 가 나은가? |
| deploy-planner LLM 모델 | claude haiku | 동일 검토 |
| G3 자동 롤백 | 활성화 | 수동 confirm 이 나은가? |
| `.deploy-hints.json` 추론 실패 시 동작 | exit 1 + 안내 | partial deploy 후 사용자 보강? |
| Caddy + Tailscale hostname 컨벤션 | `<slug>.<tailnet>.ts.net` | hetzner-master repo 컨벤션과 충돌 확인 필요 |

## 12. 구현 계획으로 넘기기 전 체크리스트

- [ ] 사용자 spec review 완료
- [ ] section 11 의 추정값 확정
- [ ] `superpowers:writing-plans` 스킬로 implementation plan 작성
- [ ] plan 의 첫 task = section 8.1 의 RED commit 5개
- [ ] plan 의 두 번째 task = section 8.2 의 GREEN 화 순서

## 13. 참고

- 직전 spec: `docs/superpowers/specs/2026-05-22-research-design-bridge.md` — 통합 `/research-design` 의 원래 설계. 본 spec 이 이를 분리·축소
- 기존 어댑터 contract: `lib/adapter_contract.md`
- 기존 design 패턴: `agents/design-builder.md`, `design-critic.md`, `design-merger.md` — 이번 작업 미사용, 향후 `/build` 자리
- 기존 deploy 스킬: `hetzner-proxmox-deploy` (claude plugin)
