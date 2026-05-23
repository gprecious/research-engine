---
description: research/<slug>/README.md + spec/spec.md 를 claude.ai/design 으로 보내 핸드오프 번들 받기
argument-hint: <slug> [--fresh] [--login-headful] [--from-url <handoff-api-url>]
---

# /design

research-engine 의 완료된 research + spec 을 입력으로 받아 claude.ai/design 에서 인터랙티브 디자인을 만들고 핸드오프 번들 (`design/handoff/`) 을 다운로드한다. build 는 사용자가 외부 툴 (v0, cursor, 직접 코딩 등) 로 진행한 뒤 `research/<slug>/app/` 에 결과를 둔다.

## Usage

```
/design 2026-05-22-ai-image-vectorization-service
/design <slug> --fresh
/design <slug> --login-headful
/design <slug> --from-url https://api.anthropic.com/v1/design/h/XXXX
```

## Pre-conditions

1. `research/<slug>/README.md` 존재
2. `research/<slug>/spec/spec.md` 존재 (없어도 동작은 하지만 design 가이드가 약해짐)
3. `.env.research-design` 에 자격증명 + Tailscale 정보
4. 실행 환경: `HERDR_ENV=1` (herdr 세션 안)

## claude.ai/design 자동 접근 실패시

cloak_login + manual_login 모두 실패하거나 디자인 생성 자동 폼이 끊기면 **즉시 멈춤**. stderr 로 출력되는 "수동 진행" 블록:

1. 브라우저로 `https://claude.ai/design` 접속 → New design → 안내된 프롬프트 붙여넣기 → 디자인 완료 대기
2. Share → "Handoff to Claude Code…" → 모달 안의 URL 복사
3. 동일한 슬러그로 `--from-url <URL>` 추가해 재실행

자동 우회 (다른 브라우저 경로, SSH 수동 로그인 등) 은 더 시도하지 않는다.

## Output

- `research/<slug>/design/handoff/` — raw claude.ai/design export
- `research/<slug>/design/runs/<ISO>/` — collect.log, screenshots/, log.jsonl

기존 `handoff/index.html` + `meta.json` 이 존재하면 자동으로 skip 한다 (cache mode). `--fresh` 로 재수집 강제 가능.

## Implementation

```
$ bash scripts/design_collect_only.sh "$ARGUMENTS"
```

자세한 흐름은 `docs/superpowers/specs/2026-05-23-research-engine-pipeline-split-design.md` 참조.
