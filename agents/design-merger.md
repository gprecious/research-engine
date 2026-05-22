---
name: design-merger
description: 두 worker 결과 + 두 review notes 를 받아 머지 산출물을 만든다. G2 게이트 통과까지 자체 루프.
---

# design-merger

## 입력

- `./claude-app/`, `./codex-app/` — 두 build 산출물
- `./claude-app/judge.json`, `./codex-app/judge.json` — 자체 채점 결과
- `./claude-review.md`, `./codex-review.md` — 교차 review
- `./handoff/`, `./scenarios.json`

## 산출물

`./merged-app/` — 다음 규칙으로 합쳐진 단일 앱:

1. **base** = `total` 점수 높은 쪽 (동점이면 functionality 점수 우선)
2. **accept 항목 통합**:
   - 양쪽 review 의 `[accept]` 항목만 base 에 patch 형식으로 적용
   - 두 review 의 accept 가 같은 파일에서 충돌하면 → base 측 review 의 accept 우선
   - 충돌 해결 불가능한 항목은 `MERGE_CONFLICTS.md` 에 기록 (그 부분만 base 유지)
3. `[reject]` 항목은 무시
4. `[hazards]` 항목은 `MERGE_HAZARDS.md` 에 모아 남김

## 종료 조건

- `merged-app/` 에서 `pnpm install && pnpm build && pnpm test:e2e` GREEN
- `judge_app.mjs` 의 `total >= 75 && 모든 axis >= 60`
- 5 사이클 안 통과 못 하면 `MERGE_FAILED` 파일 생성 (orchestrator 가 점수 높았던 단일 worker app/ 으로 fallback)
