# `2026-05-22-ai-image-vectorization-service` — `/research-design` 첫 e2e 결과

본 디렉토리는 `/research-design` 의 **첫 end-to-end 실행** 결과물 (시드 슬러그).

> **v3 업데이트 (2026-05-22 23:43 KST)** — claude.ai/design 이 페이지 파일 (`landing.jsx`, `upload.jsx`, `health.jsx`, `app.jsx`) 모두 완성. v5 handoff bundle (`handoff/v5/`) 이 정식 산출물. Next.js TSX (`app/app/*`) 는 그 bundle 의 **mechanical port** (hash router → Next.js routing 만 교체, 시각 변경 없음). E2E 3/3 PASS @ http://localhost:3000.

2회 시도, 두 번째 시도에서 진짜 디자인 산출물을 받고 그것을 적용한 working app 으로 마무리.

## 흐름 요약 — 실 실행

### Run 1 (`/design/p/d11ac0d2-...`)

| 단계 | 결과 |
|---|---|
| storageState 인증 | ✅ Mac m2 `Profile 1` (harry@qplace.kr) CDP attach → sessionKey + cf_clearance 추출 |
| Design system | QPLACE Design System (기본값) |
| 디자인 생성 | ⚠️ 부분 — "Questions timed out; go with defaults" 로 멈춤 |
| 산출물 | `styles/tokens.css` (QPLACE 디자인 시스템) + `assets/icons-sprite.svg` + `tweaks-panel.jsx` 만 |

### Run 2 (`/design/p/c13be0bc-...`) — **이게 본 결과**

| 단계 | 결과 |
|---|---|
| Design system | **None** (사용자 요청, QPLACE 의존성 제거) |
| 프롬프트 | 사전 결정사항 풍부히 포함해 timeout 회피 시도 |
| 디자인 생성 | ⚠️ 부분 — 다시 정지. `index.html` + `components.jsx` 까지만, `landing.jsx`/`upload.jsx`/`health.jsx`/`app.jsx` 는 미생성 |
| **그러나** `components.jsx` 가 진짜 디자인 산출물 — **Vectra 브랜드**: 색상 토큰 (#2f6bff brand, #0b0d12 ink, ...), `VectraMark` SVG 로고, `Nav` (sticky + BETA 뱃지), `Footer`, `Button` (4 variants) |
| Handoff API URL | `https://api.anthropic.com/v1/design/h/0bhf12pfoJm` (modal 에서 추출) |

## 디자인 → Next.js 변환

`components.jsx` 의 Vectra 브랜드 (vanilla React + Babel-in-browser 형식) 를 Next.js 14 (app router) TSX 형식으로 옮겨 다음 두 페이지에 적용:

- `app/page.tsx` — Vectra 랜딩 페이지 (sticky Nav + 히어로 + 3-column feature cards + footer). H1: "Vectorize raster art" (scenarios.json 의 `vectoriz` regex 매칭)
- `app/upload/page.tsx` — Vectra 스타일 업로드 페이지 (Nav + Convert CTA + SVG preview area with mock trace SVG)

## 기여 (claude / codex 양쪽)

| 시점 | 주체 | 기여 |
|---|---|---|
| Phase 3 (T11–T15) | Claude 어시스턴트 + subagents | `lib/design_handoff_parser.mjs` + `lib/app_scaffold.mjs` 작성. RED 테스트 GREEN. 기본 scaffold 템플릿. |
| T22 첫 시도 (`b1dfae1` commit) | Codex (`codex exec`) | Run 1 의 QPLACE tokens.css 를 `app/globals.css` 의 :root 에 임포트 + `page.tsx` 의 H1/CTA 인라인 스타일을 `var(--color-font-strong)`, `var(--color-brand)` 로 |
| T22 두 번째 시도 (본 commit) | Claude 어시스턴트 | Run 2 의 `components.jsx` Vectra 디자인 (색상·로고·Nav·Footer 패턴) 을 Next.js TSX 로 옮김. 두 페이지 (page.tsx, upload/page.tsx) 와 globals.css 갱신. |

**둘 모두 e2e 게이트 통과** — Playwright 시나리오 3/3 PASS 양쪽 모두 (RED → GREEN, 그리고 Vectra 적용 후에도 GREEN).

## G1 게이트 결과

`E2E_BASE_URL=http://localhost:3030 pnpm test:e2e`:

```
Running 3 tests using 1 worker
  ✓  1 scenarios: 2026-05-22-ai-image-vectorization-service › landing-hero-cta (515ms)
  ✓  2 scenarios: 2026-05-22-ai-image-vectorization-service › upload-and-preview (397ms)
  ✓  3 scenarios: 2026-05-22-ai-image-vectorization-service › health-and-no-runtime-error (492ms)
  3 passed (2.3s)
```

## 시각 검증

스크린샷: `/tmp/vectra-home.png`, `/tmp/vectra-upload.png` (this session 산출물, gitignored).

랜딩에 보이는 것:
- 좌상단: Vectra mark + 워드마크 + "BETA" 뱃지
- 우상단: dark CTA "Try free →" (data-testid=cta-try)
- 히어로: "raster → SVG, in seconds" pill chip + H1 "Vectorize raster art" + 부제목 + brand-blue CTA
- 3-column 기능 카드: Trace anywhere / Print-ready / Fast hand-off
- Footer: brand + © 2026 Vectra Labs

업로드에 보이는 것:
- Nav (Vectra mark + 워드마크)
- "Upload your image" + 안내문 + dropzone (soft 배경, dashed border)
- Convert primary CTA (brand blue)
- SVG preview area — Convert 클릭 시 Vectra 색상으로 그려진 mock triangle SVG

## 미달성 항목 (followup)

- **디자인 자체의 완성도**: claude.ai/design 의 "Questions timed out" 이 두 번 다 발생 — token 소진 또는 인터랙티브 답변 부재. `components.jsx` 까지는 만들었지만 페이지별 jsx 는 미완성. design_collect.mjs 에 chip 자동 클릭 + 풍부한 follow-up 메시지 패턴 반영 필요.
- **herdr 4-pane 풀 parallel orchestration**: 본 e2e 는 단일 worker (codex) + Claude 어시스턴트 직접 작업. 4-pane 풀 파이프라인은 `scripts/herdr_orchestrate.sh` 에 구현되어 있고 별도 세션에서 실행 가능.
- **G2 머지**: design-merger 미실행 (병렬 두 산출물 필요).
- **G3 LXC 배포**: hetzner-master 접근/Tailscale 인증 필요. 본 e2e 는 로컬 :3030 까지만.
- **4축 LLM judge real mode**: `JUDGE_SMOKE=1 pnpm test:unit -- judge_app` 로 별도 실행 가능.

## 핵심 발견 — plan/spec 후속 patch 포인트

`scripts/_t22_discovery/README.md` 와 `scripts/_t22_discovery/*.mjs` 의 학습:

1. **claude.ai/design 진입 흐름**: `New design` 폼 = `input[placeholder="Project name"]` + `select` (None/Default/QPLACE) + `Wireframe` / `High fidelity` 라디오 + `Create` 버튼.
2. **`networkidle` 도달 불가** (streaming) → `domcontentloaded` 사용.
3. **Hand off 는 Share 메뉴 안에**. Share → `Handoff to Claude Code…` → modal 안에 `Copy command` (API URL 포함) + `Download zip instead` (체크박스 → 별도 다운로드 트리거).
4. **`Download project as .zip`** 가 Share 메뉴 직접 항목 (가장 안정적 export).
5. **다중 Chrome profile**: `--profile-directory="Profile 1"` 필수 (사용자별 다름).
6. **"Questions timed out; go with defaults"** chip 클릭으로 회복 가능하지만 종종 충분치 않음 — 디자인이 components 단계에서 멈출 수 있음.
7. **handoff bundle 부족 시 fallback**: components.jsx 의 디자인 시스템 + 컴포넌트 패턴을 직접 추출해 Next.js scaffold 에 적용 가능. 이게 본 e2e 의 핵심 전략.
