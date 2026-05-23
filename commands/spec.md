---
description: research/<slug>/README.md + intent.json 으로 scenarios.json (TDD e2e 계약) + spec.md 생성
argument-hint: <slug>
---

# /spec

research-engine 의 완료된 research 세션 (`research/<slug>/README.md`) 을 입력으로 받아 TDD 게이트용 e2e 시나리오 (`spec/scenarios.json`) 과 사람 검토용 contract 요약 (`spec/spec.md`) 을 생성한다.

## Usage

```
/spec 2026-05-22-ai-image-vectorization-service
```

## Pre-conditions

1. `research/<slug>/README.md` 존재
2. `research/<slug>/intent.json` 존재 (optional, 없으면 빈 intent 로 진행)

## Output

- `research/<slug>/spec/scenarios.json` — `/deploy` 의 G3 게이트 입력
- `research/<slug>/spec/spec.md` — design·build 시 참고용 contract 요약
- `research/<slug>/spec/runs/<ISO>/log.jsonl`

## Gate

**G0**: ajv strict schema 통과 + scenarios ≥ 3개. 통과 못하면 LLM 1회 재시도 후 exit 1.

## Implementation

```
$ bash scripts/spec_generate.sh "$ARGUMENTS"
```

자세한 흐름은 `docs/superpowers/specs/2026-05-23-research-engine-pipeline-split-design.md` 참조.
