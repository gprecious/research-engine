---
description: research/<slug>/README.md 를 claude.ai/design 으로 디자인 → claude/codex 병렬 빌드 → hetzner-master LXC 배포
argument-hint: <slug> [--no-deploy] [--login-headful] [--fresh] [--from-url <handoff-api-url>]
---

# /research-design

research-engine 의 완료된 research 세션을 받아 실서비스급 인터랙티브 프로토타입을 만들고 hetzner-master 의 LXC 컨테이너에 배포한다.

## Usage

```
/research-design 2026-05-22-ai-image-vectorization-service
/research-design <slug> --no-deploy
/research-design <slug> --login-headful
/research-design <slug> --fresh
/research-design <slug> --from-url https://api.anthropic.com/v1/design/h/XXXX
```

## claude.ai/design 자동 접근 실패시

cloak_login + manual_login 모두 실패하거나 디자인 생성 자동 폼이 끊기면 **즉시 멈춤**.
이 때 stderr 로 출력되는 "수동 진행" 블록:

1. 브라우저로 `https://claude.ai/design` 접속 → New design → 안내된 프롬프트 붙여넣기 → 디자인 완료 대기
2. Share → "Handoff to Claude Code…" → 모달 안의 명령에서 URL 만 복사 (`https://api.anthropic.com/v1/design/h/...`)
3. 동일한 슬러그로 `--from-url <URL>` 추가해 재실행 — fetch + tsx 전사부터 자동으로 이어진다.

자동 우회 (다른 브라우저 경로, SSH 수동 로그인 등) 은 더 시도하지 않는다.

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
