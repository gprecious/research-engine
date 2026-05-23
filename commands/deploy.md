---
description: research/<slug>/app/ 를 hetzner LXC 에 배포하고 G3 (prod e2e) 게이트 통과 확인
argument-hint: <slug> [--target lxc]
---

# /deploy

사용자가 외부 툴로 build 한 `research/<slug>/app/` 디렉터리를 hetzner-master 의 LXC 컨테이너에 배포하고, `spec/scenarios.json` 의 시나리오를 prod URL 대상으로 실행해 G3 게이트를 통과하는지 확인한다.

## Usage

```
/deploy 2026-05-22-ai-image-vectorization-service
/deploy <slug> --target lxc        # 현재 LXC 만 지원
```

## Pre-conditions

1. `research/<slug>/README.md` 존재
2. `research/<slug>/spec/scenarios.json` 존재 (`/spec` 으로 생성)
3. `research/<slug>/app/` 존재 + `package.json` 포함 (사용자가 외부 툴로 작성)
4. `research/<slug>/app/.deploy-hints.json` (optional) — runtime/build/port override
5. `.env.research-design` 에 `HETZNER_MASTER_HOST`, `HETZNER_MASTER_USER`
6. hetzner-master LXC 컨테이너 안에 Tailscale 한 번 `tailscale up` 완료된 상태 (최초 1회)

## Output

- `research/<slug>/deploy/deploy.json` — `{target, host, lxc_id, deployed_at, prev_host, g3}`
- `research/<slug>/deploy/runs/<ISO>/{adapter.log, gate-3.json, log.jsonl, lxc_config.json}`
- Tailscale internal URL (`<slug>.<tailnet>.ts.net`) — stdout 마지막 줄

## Gate

**G3**: prod URL 대상 Playwright e2e (`scenarios.json` 사용) + `GET /health` 200. 실패시 stderr 에 `prev_host` 출력 (수동 revert 용 — v1 은 자동 롤백 미지원, LXC slug-idempotent 특성상 별도 설계 필요).

## Implementation

```
$ bash scripts/deploy_dispatch.sh "$ARGUMENTS"
```

자세한 흐름은 `docs/superpowers/specs/2026-05-23-research-engine-pipeline-split-design.md` 참조.
