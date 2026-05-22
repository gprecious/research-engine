---
title: research-design — claude.ai/design 핸드오프 → claude/codex 병렬 빌드 → LXC 배포 브릿지
slug: 2026-05-22-research-design-bridge
created: 2026-05-22
status: draft (awaiting user review)
---

# `/research-design <slug>` — research 결과를 클로드 디자인으로 만들어 실서비스까지 잇기

## 1. 한 줄 요약

`/research-design <slug>` 한 번으로 — claude.ai/design 자동화로 인터랙티브 프로토타입을 받고 → Claude Code 와 Codex 가 병렬로 R/N(Next.js) 앱으로 구현 → 비판적 cross-review 후 합쳐서 hetzner-master LXC 컨테이너에 배포한다. Playwright E2E 와 4축 LLM judge 둘 다 통과해야 성공.

## 2. 목적

`research/<slug>/README.md` 를 입력으로 받아, 사용자가 "바로 실사용 가능한 인터랙티브 프로토타입"을 손에 넣을 때까지 모든 단계 자동화. 사람의 개입은 (a) 최초 1회 claude.ai 로그인 (cloak-browser 가 막힐 때), (b) 최종 review 두 지점만.

## 3. 입출력

**입력**
- 필수: `research/<slug>/README.md` (research-engine `/research` 산출물)
- 시드 슬러그(첫 e2e 검증 케이스): `2026-05-22-ai-image-vectorization-service`
- 옵션: `--no-deploy` (LXC 배포 생략), `--login-headful` (cloak 건너뛰고 바로 Tailscale m4 로 가기), `--fresh` (storageState 캐시 무시)

**출력**
- `research/<slug>/design/handoff/` — claude.ai/design 의 raw handoff bundle (HTML/CSS/asset + 메타)
- `research/<slug>/design/app/` — 최종 머지된 R/N 앱 코드 (Next.js production-ready)
- `research/<slug>/design/runs/<ISO>/{claude,codex,merge}/` — 단계별 산출물 (worktree 결과, review notes, judge 점수, 스크린샷)
- `research/<slug>/design/scenarios.json` — 사전 정의된 e2e 시나리오 (사람이 작성 또는 생성, **개발 시작 전 commit**)
- `research/<slug>/design/README.md` — 진행기록 + 최종 게이트 결과 + 배포 URL
- hetzner-master 의 LXC 컨테이너 (Tailscale internal hostname)

## 4. 성공 기준 (게이트)

**3중 게이트, 모두 통과해야 성공:**

| 게이트 | 시점 | 기준 |
|---|---|---|
| G1: 병렬 빌드 | claude/codex worker 각자 자체 종료 시점 | 양쪽 모두 — Playwright e2e (`tests/research-design/e2e/<slug>.spec.ts`) PASS **그리고** 4축 LLM judge 총점 ≥ 75 **그리고** 각 축 ≥ 60 |
| G2: 머지 | merger 산출 직후 | 머지 결과물도 G1 의 동일 기준 통과 |
| G3: 프로덕션 | LXC 배포 직후 | prod URL 대상 동일 Playwright 시나리오 PASS + `GET /health` 200 |

게이트 출력은 모두 `runs/<ISO>/gate-{1,2,3}.json` 으로 보존 (judge 점수, e2e 리포트, 콘솔/네트워크 로그 요약).

## 5. 아키텍처

플러그인 (research-engine) tree 기존 패턴을 그대로 따른다 — commands/, agents/, scripts/, lib/, tests/.

### 5.1 모듈 책임

```
commands/research-design.md           사용자 진입 slash 명령 (인자 파싱, pipeline 호출)
agents/design-collector.md            claude.ai/design 자동화 페르소나
agents/design-builder.md              build worker 페르소나 (claude/codex 공통)
agents/design-critic.md               상대 PR 비판적 review 페르소나
agents/design-merger.md               두 결과 통합 페르소나
scripts/
  research_design_pipeline.sh         orchestrator (top-level)
  cloak_login.sh                      cloak-browser 자동 로그인 시도
  manual_login.sh                     Tailscale m4 Chrome 폴백
  design_collect.mjs                  playwright + storageState + handoff 다운로드
  herdr_orchestrate.sh                herdr pane 4개 띄움 (claude-build, codex-build, claude-critic, codex-critic)
  judge_app.mjs                       4축 LLM judge (visualizer-judge 패턴 차용)
  lxc_deploy.sh                       hetzner-proxmox-deploy 스킬 호출 wrapper
lib/
  design_handoff_parser.mjs           handoff bundle 파싱 (컴포넌트/asset 추출)
  app_scaffold.mjs                    Next.js 베이스 스캐폴드 + handoff 주입
tests/research-design/
  e2e/<slug>.spec.ts                  scenarios.json 을 expand 한 playwright test
  fixtures/                           e2e 입력 파일 (이미지 등)
  judge_fixture.json                  judge 모의 입출력
  pipeline.test.sh                    mock 모드 통합 테스트
```

각 모듈 — 단일 책임, 파일 또는 stdin/stdout 인터페이스로만 통신. 독립적으로 테스트 가능.

### 5.2 데이터 흐름

```
/research-design <slug>
  │
  ▼
[1] precheck — research/<slug>/README.md 존재, scenarios.json 존재 확인
  │
  ▼
[2] design_collect.mjs
    ├─ storageState 캐시 유효? → 재사용
    ├─ else cloak_login.sh (헤드리스 자동)
    └─ else manual_login.sh (Tailscale m4 Chrome, 사용자 1회 로그인)
    → claude.ai/design 진입, README 텍스트 + 핵심 sources 첨부 → 프롬프트 전송
    → "Hand off to Claude Code" 클릭 → handoff bundle 다운로드 → research/<slug>/design/handoff/
  │
  ▼
[3] herdr_orchestrate.sh : pane 분기 (병렬)
    pane "claude-build" : worktree A — `claude -p` 헤드리스 worker, design-builder prompt
    pane "codex-build"  : worktree B — `codex exec`     worker, design-builder prompt
    각 pane 은 자체 루프로 G1 게이트 통과까지 코드 수정 (max 5 회 반복)
  │
  ▼
[4] G1 평가 — 둘 다 PASS 확인. 한쪽 실패 시 그쪽만 1회 추가 재시도 → 그래도 실패면 fail-stop
  │
  ▼
[5] cross-review (병렬)
    pane "claude-critic" : codex 결과물을 비판적으로 review → notes.md (accept/reject 항목 명시)
    pane "codex-critic"  : claude 결과물을 비판적으로 review → notes.md
  │
  ▼
[6] design-merger : 점수 높은 쪽을 base + 양쪽 review notes 의 "accept" 항목만 통합
    → research/<slug>/design/app/
  │
  ▼
[7] G2 평가 — 머지 결과물 e2e + judge 재실행
  │
  ▼
[8] lxc_deploy.sh : hetzner-proxmox-deploy 스킬 호출
    → 새 LXC + Caddy + Next.js prod build + systemd + Tailscale 노드 등록
  │
  ▼
[9] G3 평가 — prod URL 대상 e2e + /health 200
  │
  ▼
[10] research/<slug>/design/README.md 업데이트, Notion sync (옵션)
```

## 6. 인증 / 봇탐지 흐름

claude.ai/design 은 Pro 이상 구독 + Anthropic 계정 로그인이 필요하고, Cloudflare/hCaptcha 가 강함. 인증은 1회성 시드로 처리 후 storageState 재사용으로 헤드리스화.

**storageState 캐시 경로**: `~/.config/research-engine/claude-design/storageState.json` (mode 0600)
**메타**: `~/.config/research-engine/claude-design/state.meta.json` — `{expires_at}`, 14일 자동 만료

**시도 순서 (fail-fast chain)**

1. **storageState 유효?** — playwright 로 `https://claude.ai/design` 진입 후 로그인 indicator(예: `[data-testid=user-menu]` 또는 그에 상응하는 셀렉터, 첫 collect 시 캡처) 존재 확인. OK 면 통과.
2. **`cloak_login.sh` (cloak-browser 자동)**
   - cloak-browser 로컬 미설치 시 자동 설치 (`npm i -g cloak-browser` 또는 동등 절차 — research/2026-05-20-cloakbrowser-… 의 README 참조)
   - stealth playwright context 로 `claude.ai/login` → 환경변수 `CLAUDE_LOGIN_EMAIL` / `CLAUDE_LOGIN_PW` 자동 입력 → storageState 저장
   - hCaptcha 또는 Cloudflare challenge 페이지 감지 시 **즉시 fail-fast** (이 단계에서 풀 시도 안 함)
3. **`manual_login.sh` (Tailscale m4 Chrome 폴백)**
   - m4 Tailscale hostname 가정: `m4` 또는 `taejin@m4` (사용자 spec review 시 정확값으로 교체 가능)
   - `ssh taejin@m4 'open -a "Google Chrome" --args --remote-debugging-port=9222 --user-data-dir=/tmp/cdp-claude-design "https://claude.ai/login"'`
   - 사용자 안내(한글 stdout): "Mac m4 의 Chrome 에서 로그인 완료 후 Enter — playwright 가 같은 프로필을 attach 합니다"
   - playwright `chromium.connectOverCDP("http://m4:9222")` (Tailscale 같은 tailnet 이므로 직결)
   - 로그인 완료 감지 후 storageState 추출 → 로컬 캐시 → m4 Chrome 종료

**로컬 모니터 없는 제약**: 모든 단계 headless 또는 m4 원격. 로컬에서 Chromium UI 띄우지 않음.

**자격증명 채널**: `.env.research-design` (gitignore) — `CLAUDE_LOGIN_EMAIL`, `CLAUDE_LOGIN_PW`, `M4_TAILSCALE_HOST` (기본 `m4`), `M4_TAILSCALE_USER` (기본 `taejin`). 사용자 spec review 시 변경 가능.

## 7. 테스트 시나리오 (TDD / Red 우선)

**모든 게이트 테스트는 본 구현 코드 한 줄 전에 commit 한다.** 사용자 요구사항.

### 7.1 Playwright e2e

`tests/research-design/e2e/<slug>.spec.ts` 가 `research/<slug>/design/scenarios.json` 을 읽어 playwright test 로 expand.

**시드 슬러그(`2026-05-22-ai-image-vectorization-service`) 시나리오 예시:**

```json
{
  "$schema": "../schemas/scenarios.schema.json",
  "slug": "2026-05-22-ai-image-vectorization-service",
  "baseUrl": { "local": "http://localhost:3000", "prod": "https://<lxc-host>" },
  "scenarios": [
    {
      "name": "landing-hero-cta",
      "steps": [
        { "goto": "/" },
        { "expect": { "selector": "h1", "containsText": "vectoriz" } },
        { "click": "[data-testid=cta-try]" },
        { "expect": { "url": "/upload" } }
      ]
    },
    {
      "name": "upload-and-preview",
      "steps": [
        { "goto": "/upload" },
        { "setInputFiles": ["input[type=file]", "tests/research-design/fixtures/sample.png"] },
        { "click": "[data-testid=convert]" },
        { "waitForSelector": "[data-testid=svg-preview] svg", "timeout": 15000 },
        { "expectNoConsoleError": true }
      ]
    },
    {
      "name": "health-and-no-runtime-error",
      "steps": [
        { "fetch": "/health", "expectStatus": 200 },
        { "goto": "/" },
        { "expectNoConsoleError": true },
        { "expectNoNetworkFailure": ["/_next/", "/api/"] }
      ]
    }
  ]
}
```

스키마: `tests/research-design/schemas/scenarios.schema.json` 으로 strict validate.

**주의** — `[data-testid=…]` 셀렉터는 e2e-friendliness 를 위해 claude/codex builder 의 책임이다. handoff bundle 의 원본에는 testid 가 없을 수 있다. `agents/design-builder.md` 의 지시서에 명시: "시나리오 셀렉터가 가리키는 모든 element 에 `data-testid` 를 추가해 e2e 가 가능하게 한다." 즉 G1 은 worker 출력 대상 (raw handoff 자체는 게이트 대상이 아님).

### 7.2 4축 LLM judge

`scripts/judge_app.mjs` — 기존 `agents/visualizer-judge.md` 의 rubric 차용. 입력: `app/` 의 정적 스크린샷(playwright `browser_take_screenshot` 으로 holding 후) + handoff 원본 디자인 스크린샷 + `scenarios.json`. 출력 `{designQuality, originality, craft, functionality, total, axisNotes}`.
- 게이트: total ≥ 75 **그리고** 모든 축 ≥ 60 (단일 축 망함 방지)

### 7.3 unit / integration

- `lib/design_handoff_parser.test.mjs` — handoff bundle 파싱, snapshot 기반 (fixture 하나 미리 캡처. 첫 collect 후 fixture 갱신 PR.)
- `scripts/pipeline.test.sh` — pipeline mock 모드: handoff fixture + claude/codex stdout mock — pipeline 의 단계 전이 + 게이트 평가 로직만 검증

### 7.4 Red 상태 commit 순서

1. `tests/research-design/schemas/scenarios.schema.json` + `tests/research-design/e2e/<slug>.spec.ts` (시드 슬러그) + scenarios.json (시드)
2. `scripts/judge_app.mjs` 의 인터페이스 + judge_fixture.json (기대 점수 미달)
3. `lib/design_handoff_parser.test.mjs` (스냅샷 없는 상태)
4. `scripts/pipeline.test.sh` (mock 도 없는 상태)

→ 위 4종 모두 RED 인 상태로 commit, 본 구현은 그 다음.

## 8. 오류 처리 & 폴백

| 단계 | 실패 모드 | 처리 |
|---|---|---|
| storageState attach | 만료/무효 | 자동 폐기 → cloak-browser 단계로 |
| cloak_login | hCaptcha/Cloudflare 감지 | 즉시 fail-fast → manual_login 폴백 |
| manual_login | ssh/CDP 실패 | 사용자에게 한글 에러 + 수동 절차 안내 후 stop |
| handoff 다운로드 | 셀렉터 변경/타임아웃 | 1회 재시도 → 실패 시 screenshot + console + network 덤프 → stop |
| claude-build / codex-build | G1 게이트 실패 | 해당 워커만 1회 추가 재실행 → 둘 다 못 통과 시 stop |
| cross-review LLM | LLM 호출 실패 | review 없이 점수 높은 쪽 base 로 머지 진행 (degraded 모드 표시) |
| merge | G2 게이트 실패 | 점수 높았던 단일 워커 산출물로 fallback, 메타 `merge-degraded` |
| LXC 배포 | proxmox 호출 실패 | 로컬 빌드 보존, deploy skip, README 명시, exit 1 |
| G3 (prod) | prod e2e 실패 | 이전 컨테이너로 자동 롤백(존재 시), README 명시 |

전 단계 `research/<slug>/design/runs/<ISO>/log.jsonl` 에 step-event 누적.

## 9. 외부 의존성

- `playwright` — npm 패키지 (plugin/playwright MCP 와 별개로 e2e/collect 양쪽에서 사용)
- `cloak-browser` — npm 패키지, lazy install
- `herdr` — `/home/taejin/.local/bin/herdr` (이미 PATH), HERDR_ENV=1 일 때 in-session pane 추가
- `claude` — `~/.local/bin/claude`, `claude -p "<prompt>"` 헤드리스 worker
- `codex` — `/usr/bin/codex`, `codex exec "<prompt>"` 헤드리스 worker
- `hetzner-proxmox-deploy` 스킬 — LXC 생성/관리
- Tailscale 네트워크 — m4 mac 직결
- Notion (옵션) — 기존 `scripts/push_to_notion.sh` 재사용

## 10. hetzner-master LXC 배포 사양

`hetzner-proxmox-deploy` 스킬 발동, 컨테이너 사양:
- Debian 12 minimal LXC 템플릿 (hetzner-master 의 최소 사양 템플릿 — `gprecious/hetzner-master` repo 의 default)
- 1 vCPU, 1 GB RAM, 10 GB disk (Next.js prod 충분)
- Tailscale subnet 노드 자동 등록 → internal hostname (예: `<slug>.<tailnet>.ts.net`)
- 내부 스택: `node 22 + pnpm + caddy`
- `pnpm build && pnpm start` 을 systemd unit `research-design-app.service` 로 항상 running
- Caddy 가 `:443` → next prod 서버로 reverse proxy (TLS 는 Tailscale serve 또는 Caddy internal CA)
- `lxc_deploy.sh` idempotent — 같은 slug 재배포 시 동일 컨테이너 업데이트

## 11. YAGNI — 의도적으로 안 하는 것

- 다중 슬러그 동시 처리 (한 번에 한 슬러그)
- 디자인 variation 비교 GUI (CLI / 파일 산출물만)
- 사용자 정의 디자인 시스템 입력 (claude.ai/design 의 onboarding 자동 추출에 위임)
- 컨테이너 비용 모니터링·자동 종료 (수동 관리)
- 자격증명 vault 통합 (.env 로 충분)
- 모바일 viewport 별도 시나리오 (첫 시드는 desktop 만)

## 12. 본 spec 의 추정 / 사용자 review 에서 확정해야 할 값

| 항목 | 본 spec 의 가정값 | 사용자 검토 포인트 |
|---|---|---|
| m4 Tailscale hostname | `m4` | Tailscale magic DNS 이름 또는 100.x.x.x |
| m4 ssh user | `taejin` | 다른 사용자명? |
| 자격증명 채널 | `.env.research-design` 환경변수 (gitignore) — `CLAUDE_LOGIN_EMAIL`, `CLAUDE_LOGIN_PW`, `M4_TAILSCALE_HOST`, `M4_TAILSCALE_USER` | 다른 secret 채널 필요 시 변경 |
| handoff bundle 구조 | 첫 collect 시 capture → `lib/design_handoff_parser.mjs` reverse-engineer | 동의? (대안: 사용자가 sample handoff 미리 제공) |
| 첫 시드 슬러그 시나리오 | 위 7.1 의 3개 시나리오 | 추가/변경할 시나리오? |
| LXC 사양 (1vCPU/1GB/10GB) | 최소 사양 | 더 큰 사양 필요? |

## 13. 구현 계획으로 넘기기 전 체크리스트

- [ ] 사용자 spec review 완료
- [ ] section 12 의 추정값 확정
- [ ] `superpowers:writing-plans` 스킬로 implementation plan 작성
- [ ] plan 의 첫 task = RED 테스트 작성 (section 7.4 의 4종)
- [ ] plan 의 두 번째 task = pipeline orchestrator skeleton (mock 통과)
- [ ] 그 이후 — 각 모듈 GREEN 화

## 14. 참고

- 기존 research: `research/2026-04-18-claude-design-anthropic-labs/README.md` (제품 자체 분석, handoff 가 핵심 차별점)
- 기존 research: `/home/taejin/research/2026-05-20-cloakbrowser-made-claude-agents-undetect/` (cloak-browser 우회 기법)
- 기존 스킬: `hetzner-proxmox-deploy`, `superpowers:using-git-worktrees`, `superpowers:dispatching-parallel-agents`, `herdr`
- 기존 패턴: `commands/research-visualize.md`, `scripts/render_chart.sh`, `agents/visualizer-judge.md` — 본 spec 의 명령/스크립트/judge 구조 참조본
