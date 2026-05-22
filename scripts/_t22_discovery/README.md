# T22 Discovery Scripts (one-off)

`/research-design` 의 첫 e2e 실행 (`2026-05-22-ai-image-vectorization-service`) 에서 발견한
claude.ai/design 실 DOM/흐름에 적응하기 위해 작성한 scratch 스크립트들.

| 파일 | 역할 | 발견 사항 |
|---|---|---|
| `_collect_e2e_discovery.mjs` | 첫 collect 흐름 시도 | New design 폼: `input[placeholder=Project name]` → `Create` 버튼. URL 패턴 `/design/p/<uuid>`. |
| `_collect_e2e_resume.mjs` | 기존 design URL 재진입 + handoff 폴링 | `Hand off` 버튼은 페이지에 직접 없음 → Share 메뉴 안에 있음. 디자인 진행 중에는 `networkidle` 도달 못함 → `domcontentloaded` 로 변경. |
| `_collect_e2e_unblock.mjs` | "Questions timed out; go with defaults" chip 클릭 + Share 메뉴 dump | Share 메뉴 항목: `Copy link`, `Duplicate project`, `Duplicate as template`, `Download project as .zip`, `Export as PDF`, `Export as PPTX…`, `Send to Canva…`, `Export as standalone HTML`, **`Handoff to Claude Code…`**. |
| `_collect_e2e_handoff.mjs` | `Handoff to Claude Code…` 모달 + `Download project as .zip` 동시 시도 | Handoff modal 의 메인 페이로드: `Fetch this design file ... https://api.anthropic.com/v1/design/h/<id>` (API URL). 디자인 파일 직접 다운로드는 별도 `Download project as .zip` 항목. |

## 이걸 design_collect.mjs 에 반영해야 할 patch (followup work)

1. 진입 흐름 — `https://claude.ai/design` → `input[placeholder*=Project name]` 채우기 → `button:has-text(Create)` → URL 변화 대기 (`/design/p/`).
2. 페이지 로딩 — `domcontentloaded` 만 사용 (networkidle 은 streaming 으로 도달 불가).
3. Handoff 경로 — 단일 버튼 시도하지 말고 직접 `Share` 메뉴 열기 → `text=/Handoff to Claude Code/i` 클릭 → 모달 안의 `Copy command` 또는 `Download zip instead` 활용.
4. Handoff URL 보존 — 모달 내 `https://api.anthropic.com/v1/design/h/<id>` 를 handoff.meta.json 에 저장 (API 로 full bundle 재취득 가능).
5. 디자인 timeout 회복 — "Questions timed out; go with defaults" chip 자동 클릭 또는 follow-up 프롬프트로 진행.
6. 다중 profile 환경 — Chrome `--profile-directory="Profile 1"` (사용자별 다름). storageState 캡처 시 사용자가 자신의 정확한 profile 을 가져와야 함.

본 디렉토리의 스크립트는 단일-사용 (`2026-05-22-ai-image-vectorization-service` 시드 슬러그 e2e) 이지만,
위 발견은 `scripts/design_collect.mjs` 의 다음 릴리스에 반영되어야 한다.
