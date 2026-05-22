---
description: research/<slug>/README.md 를 claude.ai/design 으로 디자인 → claude/codex 병렬 빌드 → hetzner-master LXC 배포
argument-hint: <slug> [--no-deploy] [--login-headful] [--fresh]
---

# /research-design

research-engine 의 완료된 research 세션을 받아 실서비스급 인터랙티브 프로토타입을 만들고 hetzner-master 의 LXC 컨테이너에 배포한다.

## Usage

```
/research-design 2026-05-22-ai-image-vectorization-service
/research-design <slug> --no-deploy
/research-design <slug> --login-headful
/research-design <slug> --fresh
```

## Pre-conditions

1. `research/<slug>/README.md` 존재
2. `research/<slug>/design/scenarios.json` 존재 — TDD 게이트 입력
3. `.env.research-design` 에 자격증명 + Tailscale 정보
4. 실행 환경: `HERDR_ENV=1` (herdr 세션 안)

## Output

- `research/<slug>/design/handoff/` — raw claude.ai/design export
- `research/<slug>/design/app/` — 최종 머지된 Next.js 앱
- `research/<slug>/design/runs/<ISO>/` — 단계별 산출물 + log.jsonl + gate JSON
- Tailscale internal URL — `research/<slug>/design/runs/<ISO>/host.txt`

## Implementation

```
$ bash scripts/research_design_pipeline.sh "$ARGUMENTS"
```

자세한 흐름은 `docs/superpowers/specs/2026-05-22-research-design-bridge.md` 참조.
