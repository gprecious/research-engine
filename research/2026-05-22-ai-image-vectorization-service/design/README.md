# `2026-05-22-ai-image-vectorization-service` — design pipeline 첫 e2e 결과

본 디렉토리는 `/research-design` 의 **첫 end-to-end 실행** 결과물 (시드 슬러그). 미완성 상태이지만 파이프라인 핵심 흐름이 모두 한 번씩 작동했음을 입증.

## 흐름 요약 (실 실행)

| 단계 | 결과 |
|---|---|
| storageState 인증 | ✅ Mac m2 의 Chrome `Profile 1` (harry@qplace.kr) CDP attach → cookies (sessionKey + cf_clearance) 추출 |
| 디자인 생성 | ⚠️ 부분 완료 — Claude 가 사용자에게 명확화 질문 → 응답 timeout → "Questions timed out; go with defaults" 상태로 멈춤 |
| Handoff bundle | ✅ Share 메뉴 → `Handoff to Claude Code…` 모달 발견. API URL `https://api.anthropic.com/v1/design/h/6pP53sgjg3JIfdsiMmMx8A` 노출. 별도로 `Download project as .zip` 로 파일 추출 (`assets/icons-sprite.svg`, `styles/tokens.css`, `tweaks-panel.jsx`) |
| Parser → Scaffold | ✅ `lib/design_handoff_parser.mjs` + `lib/app_scaffold.mjs` 로 Next.js 14 app router 앱 생성. QPLACE 디자인 시스템 토큰을 `handoff.meta.json` 의 designSystem 으로 주입 |
| Claude 기여 (build) | ✅ 본 어시스턴트 + subagent 들이 `lib/app_scaffold.mjs` 의 콘텐츠로 베이스 앱 생성 |
| Codex 기여 (enhance) | ✅ `codex exec --dangerously-bypass-approvals-and-sandbox` 한 번 호출로 QPLACE `:root` 토큰 풀 셋을 `app/globals.css` 에 임포트 + `app/page.tsx` 의 H1/CTA 인라인 스타일을 `var(--color-font-strong)`, `var(--color-brand)` 로 변경 + `pnpm build` 통과 |
| G1 e2e (Playwright) | ✅ **3/3 PASS** (`landing-hero-cta`, `upload-and-preview`, `health-and-no-runtime-error`) — codex 변경 적용 후에도 GREEN |

## 핵심 산출물

- `scenarios.json` — 사전 정의 e2e 시나리오 (Phase 1 RED commit, Phase 5 GREEN)
- `handoff/styles/tokens.css` — QPLACE 디자인 시스템 (Tailwind 4 @theme 형식)
- `handoff/tweaks-panel.jsx` — design 산출물 React 컴포넌트 (참고 자료)
- `handoff/handoff.meta.json` — 추출한 design system 메타 + handoff URL
- `handoff/design-screenshot.png` — 디자인 페이지 스냅샷 (judge 입력 후보)
- `app/` — Next.js 14 production-ready 앱 (Claude scaffold + Codex tokens enhancement)

## 미달성 항목 (followup)

- **디자인 자체 완성**: "Questions timed out" 회복 자동화 필요 (default chip 자동 클릭 + 후속 프롬프트).
- **herdr 4-pane 풀 parallel orchestration**: claude-build + codex-build 동시 실행 + claude-critic + codex-critic 양방향 cross-review. 본 e2e 에서는 단일 worker (codex) enhancement 만 실행.
- **G2 머지**: design-merger 미실행 (병렬 결과물 없음).
- **G3 LXC 배포**: hetzner-master 접근/Tailscale 인증 필요 — 본 e2e 는 `--no-deploy` 등가 (로컬 :3030 에서만 검증).
- **4축 LLM judge**: `scripts/judge_app.mjs` real 모드 미실행 (mock 만 통과).

위는 모두 `docs/superpowers/plans/2026-05-22-research-design-bridge.md` 의 후속 작업.

## 핵심 발견 — 본 e2e 가 plan/spec 에 추가해야 할 내용

`scripts/_t22_discovery/README.md` 참조. 요약:

- claude.ai/design 진입 흐름: `Project name → Create → /design/p/<uuid>` (단순 `New design` 버튼 아님)
- Handoff 는 페이지 버튼이 아니라 Share 메뉴 안의 `Handoff to Claude Code…`
- 페이지 streaming 때문에 `networkidle` 도달 불가 → `domcontentloaded` 사용
- 다중 Chrome profile 환경에서 `--profile-directory="Profile 1"` 필수
- "Questions timed out; go with defaults" chip 으로 회복 가능
