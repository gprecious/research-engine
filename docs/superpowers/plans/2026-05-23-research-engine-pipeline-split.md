# research-engine pipeline split (/spec, /design, /deploy) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 통합 `/research-design` 을 책임 단위로 `/spec`, `/design`, `/deploy` 3개 슬래시 커맨드로 분리한다. 사용자가 design 후 외부 툴로 직접 build 한 `app/` 를 hetzner LXC 에 자동 배포할 수 있게 만든다.

**Architecture:** Stage 마다 `commands/<name>.md` (slash 진입) + `scripts/<name>_*.sh` (orchestration) + 필요시 `agents/<name>-*.md` (LLM 디스패치) 의 3-tuple. Stage 간 통신은 filesystem contract 파일 (`spec/scenarios.json`, `design/handoff/meta.json`, `app/.deploy-hints.json`, `deploy/deploy.json`) 만. orchestrator (`/ship`) 와 자동화된 `/build` 는 이번 plan 의 scope 밖.

**Tech Stack:** Node.js (ESM, vitest, ajv), bash, bats, playwright. 기존 `research_design_env.mjs`·`design_collect.mjs`·`cloak_login.mjs`·`manual_login.mjs` 재사용. 신규 npm 의존성 없음 (`ajv` 는 이미 devDep).

**Spec:** `docs/superpowers/specs/2026-05-23-research-engine-pipeline-split-design.md`

---

## File Structure

**Create (new files):**
- `lib/scenarios_validator.mjs` — ajv strict validator (G0 게이트)
- `lib/scenarios_validator.test.mjs` — vitest unit (3 fixtures)
- `tests/research-engine/schemas/scenarios.schema.json` — 기존 schema 의 신위치 + `_meta` optional field
- `tests/research-engine/fixtures/scenarios-valid.json`
- `tests/research-engine/fixtures/scenarios-missing-field.json`
- `tests/research-engine/fixtures/scenarios-with-meta.json`
- `tests/research-engine/fixtures/handoff-sample/index.html` — design fixture
- `tests/research-engine/fixtures/handoff-sample/meta.json`
- `tests/research-engine/fixtures/app-sample/package.json` — deploy fixture
- `tests/research-engine/spec.test.sh` — bats, `/spec` mock 검증
- `tests/research-engine/design.test.sh` — bats, `/design` cache mode 검증
- `tests/research-engine/deploy.test.sh` — bats, `/deploy` LXC stub + G3 mock
- `tests/research-engine/mock-bin/ssh` — `/deploy` 테스트용 ssh mock
- `tests/research-engine/mock-bin/scp` — `/deploy` 테스트용 scp mock
- `tests/research-engine/e2e/playwright.config.ts` — G3 e2e config
- `tests/research-engine/e2e/scenarios.spec.ts` — generic scenarios runner (existing runner.ts 재사용)
- `commands/spec.md` — `/spec <slug>` 진입
- `commands/design.md` — `/design <slug>` 진입 (research-design.md 의 rewrite)
- `commands/deploy.md` — `/deploy <slug>` 진입
- `agents/spec-author.md` — LLM persona for scenarios 생성
- `agents/deploy-planner.md` — LLM persona for LXC 사양 추론
- `scripts/spec_generate.sh` — `/spec` 본체
- `scripts/design_collect_only.sh` — `/design` 본체 (design_collect.mjs wrapper)
- `scripts/deploy_dispatch.sh` — `/deploy` 본체 (--target 분기)

**Move/rename:**
- `scripts/lxc_deploy.sh` → `scripts/deploy_lxc.sh`

**Delete:**
- `commands/research-design.md`
- `scripts/research_design_pipeline.sh`
- `tests/research-design/pipeline.test.sh`

**Modify:**
- `package.json` — `test:bats` script 신규 경로로 갱신, `test:unit` 에 lib/ 추가

---

## Task 1: scenarios_validator — schema 이동 + RED tests

**Files:**
- Create: `tests/research-engine/schemas/scenarios.schema.json`
- Create: `tests/research-engine/fixtures/scenarios-valid.json`
- Create: `tests/research-engine/fixtures/scenarios-missing-field.json`
- Create: `tests/research-engine/fixtures/scenarios-with-meta.json`
- Create: `lib/scenarios_validator.test.mjs`

- [ ] **Step 1: 기존 schema 를 신위치로 복사 + `_meta` optional field 추가**

```bash
mkdir -p tests/research-engine/schemas
cp tests/research-design/schemas/scenarios.schema.json tests/research-engine/schemas/scenarios.schema.json
```

이어서 `tests/research-engine/schemas/scenarios.schema.json` 최상위 `properties` 에 `_meta` 추가:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://gprecious/research-engine/schemas/scenarios.json",
  "title": "research-engine e2e scenarios",
  "type": "object",
  "required": ["slug", "baseUrl", "scenarios"],
  "additionalProperties": false,
  "properties": {
    "$schema": { "type": "string" },
    "slug": { "type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$" },
    "baseUrl": {
      "type": "object",
      "required": ["local"],
      "properties": {
        "local": { "type": "string", "format": "uri" },
        "prod": { "type": "string", "format": "uri" }
      }
    },
    "scenarios": {
      "type": "array",
      "minItems": 3,
      "items": {
        "type": "object",
        "required": ["name", "steps"],
        "properties": {
          "name": { "type": "string", "pattern": "^[a-z0-9-]+$" },
          "steps": {
            "type": "array",
            "minItems": 1,
            "items": {
              "type": "object",
              "oneOf": [
                { "required": ["goto"], "properties": { "goto": { "type": "string" } } },
                { "required": ["click"], "properties": { "click": { "type": "string" } } },
                { "required": ["setInputFiles"], "properties": { "setInputFiles": { "type": "array", "minItems": 2, "items": { "type": "string" } } } },
                { "required": ["waitForSelector"], "properties": { "waitForSelector": { "type": "string" }, "timeout": { "type": "integer" } } },
                { "required": ["expect"], "properties": { "expect": { "type": "object" } } },
                { "required": ["fetch"], "properties": { "fetch": { "type": "string" }, "expectStatus": { "type": "integer" } } },
                { "required": ["expectNoConsoleError"], "properties": { "expectNoConsoleError": { "type": "boolean" } } },
                { "required": ["expectNoNetworkFailure"], "properties": { "expectNoNetworkFailure": { "type": "array", "items": { "type": "string" } } } }
              ]
            }
          }
        }
      }
    },
    "_meta": {
      "type": "object",
      "required": ["generated_by", "generated_at", "source_intent_hash"],
      "properties": {
        "generated_by": { "type": "string" },
        "generated_at": { "type": "string", "format": "date-time" },
        "source_intent_hash": { "type": "string", "pattern": "^[a-f0-9]{64}$" }
      }
    }
  }
}
```

핵심 변경: `additionalProperties: false`, `scenarios.minItems: 3`, `_meta` optional.

- [ ] **Step 2: 3개 fixture 작성**

`tests/research-engine/fixtures/scenarios-valid.json`:

```json
{
  "slug": "2026-05-23-test-fixture",
  "baseUrl": { "local": "http://localhost:3000", "prod": "https://example.ts.net" },
  "scenarios": [
    {
      "name": "landing",
      "steps": [
        { "goto": "/" },
        { "expect": { "selector": "h1" } },
        { "expectNoConsoleError": true }
      ]
    },
    {
      "name": "second-flow",
      "steps": [
        { "goto": "/about" },
        { "expectNoConsoleError": true }
      ]
    },
    {
      "name": "health",
      "steps": [
        { "fetch": "/health", "expectStatus": 200 }
      ]
    }
  ]
}
```

`tests/research-engine/fixtures/scenarios-missing-field.json`:

```json
{
  "slug": "2026-05-23-bad",
  "scenarios": []
}
```

(baseUrl 누락, scenarios empty — 두 가지 위반)

`tests/research-engine/fixtures/scenarios-with-meta.json`: scenarios-valid.json 과 동일 + `_meta` 추가:

```json
{
  "slug": "2026-05-23-test-fixture",
  "baseUrl": { "local": "http://localhost:3000", "prod": "https://example.ts.net" },
  "scenarios": [
    { "name": "landing", "steps": [{ "goto": "/" }, { "expect": { "selector": "h1" } }, { "expectNoConsoleError": true }] },
    { "name": "second-flow", "steps": [{ "goto": "/about" }, { "expectNoConsoleError": true }] },
    { "name": "health", "steps": [{ "fetch": "/health", "expectStatus": 200 }] }
  ],
  "_meta": {
    "generated_by": "spec-author@abc1234",
    "generated_at": "2026-05-23T10:00:00.000Z",
    "source_intent_hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  }
}
```

- [ ] **Step 3: validator test 작성 (RED)**

`lib/scenarios_validator.test.mjs`:

```javascript
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { validateScenarios } from './scenarios_validator.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const fix = (name) => JSON.parse(readFileSync(resolve(__dirname, `../tests/research-engine/fixtures/${name}`), 'utf8'));

describe('scenarios_validator', () => {
  it('accepts valid scenarios', () => {
    const result = validateScenarios(fix('scenarios-valid.json'));
    expect(result.valid).toBe(true);
    expect(result.errors).toEqual([]);
  });

  it('rejects scenarios missing required fields', () => {
    const result = validateScenarios(fix('scenarios-missing-field.json'));
    expect(result.valid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors.some(e => /baseUrl/.test(e.instancePath + e.message))).toBe(true);
  });

  it('accepts scenarios with optional _meta field', () => {
    const result = validateScenarios(fix('scenarios-with-meta.json'));
    expect(result.valid).toBe(true);
  });
});
```

- [ ] **Step 4: 테스트 실행 — RED 확인**

```bash
pnpm vitest run lib/scenarios_validator.test.mjs
```

Expected: FAIL — `Cannot find module './scenarios_validator.mjs'`

- [ ] **Step 5: Commit RED**

```bash
git add tests/research-engine/schemas tests/research-engine/fixtures lib/scenarios_validator.test.mjs
git commit -m "test(scenarios-validator): RED — schema move + 3 fixtures + ajv strict tests"
```

---

## Task 2: scenarios_validator.mjs — GREEN

**Files:**
- Create: `lib/scenarios_validator.mjs`

- [ ] **Step 1: validator 구현**

`lib/scenarios_validator.mjs`:

```javascript
import Ajv from 'ajv';
import addFormats from 'ajv-formats';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const schemaPath = resolve(__dirname, '../tests/research-engine/schemas/scenarios.schema.json');
const schema = JSON.parse(readFileSync(schemaPath, 'utf8'));

const ajv = new Ajv({ allErrors: true, strict: false });
addFormats(ajv);
const validate = ajv.compile(schema);

export function validateScenarios(obj) {
  const valid = validate(obj);
  return {
    valid,
    errors: (validate.errors || []).map(e => ({
      instancePath: e.instancePath,
      message: e.message,
      keyword: e.keyword,
      params: e.params
    }))
  };
}

export function validateScenariosFile(path) {
  const obj = JSON.parse(readFileSync(path, 'utf8'));
  return validateScenarios(obj);
}
```

- [ ] **Step 2: 테스트 실행 — GREEN 확인**

```bash
pnpm vitest run lib/scenarios_validator.test.mjs
```

Expected: 3 tests PASS

- [ ] **Step 3: Commit GREEN**

```bash
git add lib/scenarios_validator.mjs
git commit -m "feat(scenarios-validator): GREEN — ajv strict validator with _meta support"
```

---

## Task 3: `/spec` test — RED

**Files:**
- Create: `tests/research-engine/spec.test.sh`
- Create: `tests/research-engine/mock-bin/claude`

bats 패턴을 따른다 (기존 `tests/research-design/pipeline.test.sh` 와 동일 구조). LLM 호출은 mock-bin/claude 로 stub.

- [ ] **Step 1: claude CLI mock 작성**

`tests/research-engine/mock-bin/claude`:

```bash
#!/usr/bin/env bash
# Mock claude CLI for /spec tests.
# Inspects args (-p mode prompt) for "spec-author" marker, emits a fixed scenarios+spec_md wrapper to stdout.

set -e

# All args concatenated. claude -p invocation: claude -p --append-system-prompt "..." "user prompt"
all_args="$*"
if echo "$all_args" | grep -q "spec-author"; then
  cat <<'JSON'
```json
{
  "scenarios": {
    "slug": "2026-05-23-spec-test-fixture",
    "baseUrl": { "local": "http://localhost:3000", "prod": "https://2026-05-23-spec-test-fixture.ts.net" },
    "scenarios": [
      { "name": "landing", "steps": [{ "goto": "/" }, { "expect": { "selector": "h1" } }, { "expectNoConsoleError": true }] },
      { "name": "flow-two", "steps": [{ "goto": "/about" }, { "expectNoConsoleError": true }] },
      { "name": "health", "steps": [{ "fetch": "/health", "expectStatus": 200 }] }
    ]
  },
  "spec_md": "# Test spec\n\nGenerated by mock-claude for spec.test.sh"
}
```
JSON
else
  echo "[mock-claude] unexpected prompt" >&2
  exit 1
fi
```

```bash
chmod +x tests/research-engine/mock-bin/claude
```

- [ ] **Step 2: bats test 작성**

`tests/research-engine/spec.test.sh`:

```bash
#!/usr/bin/env bats

setup() {
  export PATH="$(pwd)/tests/research-engine/mock-bin:$PATH"
  export RESEARCH_ENGINE_SPEC_MOCK=1
  SLUG="2026-05-23-spec-test-fixture"
  TARGET="research/${SLUG}"
  mkdir -p "${TARGET}"
  cat > "${TARGET}/README.md" <<EOF
# Test fixture for /spec
Generated by spec.test.sh setup.
EOF
  cat > "${TARGET}/intent.json" <<'JSON'
{ "purpose": "test", "focus": "scenarios generation", "audience_level": "engineer", "notes": "" }
JSON
}

teardown() {
  rm -rf "research/2026-05-23-spec-test-fixture"
}

@test "spec script exists and is executable" {
  [ -x scripts/spec_generate.sh ]
}

@test "spec rejects missing slug" {
  run scripts/spec_generate.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"slug required"* ]]
}

@test "spec rejects non-existent slug" {
  run scripts/spec_generate.sh "nope-doesnt-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
}

@test "spec generates scenarios.json with valid schema + _meta + spec.md" {
  run scripts/spec_generate.sh "2026-05-23-spec-test-fixture"
  [ "$status" -eq 0 ]
  [ -f "research/2026-05-23-spec-test-fixture/spec/scenarios.json" ]
  [ -f "research/2026-05-23-spec-test-fixture/spec/spec.md" ]
  jq -e '._meta.source_intent_hash' "research/2026-05-23-spec-test-fixture/spec/scenarios.json"
  jq -e '.scenarios | length >= 3' "research/2026-05-23-spec-test-fixture/spec/scenarios.json"
}

@test "spec writes runs/<ISO>/log.jsonl" {
  scripts/spec_generate.sh "2026-05-23-spec-test-fixture"
  ls research/2026-05-23-spec-test-fixture/spec/runs/ | grep -q '^[0-9]'
}
```

- [ ] **Step 3: package.json 의 test:bats 갱신**

`package.json` 의 scripts 섹션 수정:

```json
"test:bats": "bats tests/research-engine/spec.test.sh tests/research-engine/design.test.sh tests/research-engine/deploy.test.sh"
```

- [ ] **Step 4: 테스트 실행 — RED 확인**

```bash
chmod +x tests/research-engine/spec.test.sh
pnpm test:bats
```

Expected: FAIL — `not executable: scripts/spec_generate.sh` (script 미존재)

- [ ] **Step 5: Commit RED**

```bash
git add tests/research-engine/spec.test.sh tests/research-engine/mock-bin/claude package.json
git commit -m "test(spec): RED — /spec bats test + mock claude CLI"
```

---

## Task 4: agents/spec-author.md

**Files:**
- Create: `agents/spec-author.md`

- [ ] **Step 1: agent persona 작성**

`agents/spec-author.md`:

```markdown
---
name: spec-author
description: research/<slug>/README.md + intent.json 을 입력으로 받아 scenarios.json (TDD e2e 계약) + spec.md (사람 읽는 요약) 을 생성하는 LLM persona.
---

# spec-author

## 너의 역할

너는 research-engine 파이프라인의 **spec author** 다. 너의 산출물은 `/deploy` 단계의 G3 게이트가 prod URL 대상으로 실행할 Playwright e2e 시나리오 (`scenarios.json`) 과 인간 검토용 contract 요약 (`spec.md`) 이다.

## 입력 (prompt 본문 안에 첨부된 JSON 블록 — fenced ```json)

```json
{
  "slug": "<slug>",
  "readme": "<README.md 전체 내용>",
  "intent": { "purpose": "...", "focus": "...", "audience_level": "...", "notes": "..." },
  "intent_hash": "<sha256 of intent.json>",
  "schema_path": "tests/research-engine/schemas/scenarios.schema.json"
}
```

## 산출물 (stdout, fenced JSON 블록 한 개)

```json
{
  "scenarios": { ... scenarios.json 전체 ... },
  "spec_md": "<spec.md markdown 본문>"
}
```

## 작성 규칙

1. **scenarios**:
   - `slug` 는 입력의 slug 그대로
   - `baseUrl.local` = `"http://localhost:3000"`, `baseUrl.prod` = `"https://<slug>.ts.net"` (Tailscale internal hostname placeholder)
   - `scenarios` 배열에 **최소 3개** 시나리오:
     - 한 개는 landing page 검증 (`goto: "/"` + `expect.selector` + `expectNoConsoleError`)
     - 한 개는 README 가 묘사하는 핵심 user flow (예: 업로드, 검색, 변환 등 — README 에서 추출)
     - 한 개는 `/health` endpoint 검증 (`fetch: "/health"`, `expectStatus: 200`)
   - 모든 시나리오에 `expectNoConsoleError: true` step 최소 1개
   - 셀렉터는 `[data-testid=...]` 우선 (user 가 build 시 testid 를 심을 것이라는 contract)
   - `_meta.generated_by`, `_meta.generated_at`, `_meta.source_intent_hash` 채움
2. **spec.md**:
   - 한글
   - 섹션: 목적 / 핵심 user flow / 통과해야 할 시나리오 요약 / 빌드시 주의사항 (testid 심기, /health endpoint 추가 등)
   - 200~400 자 분량
3. `scenarios.schema.json` 의 strict 검증을 통과하도록 작성. additionalProperties:false 임을 기억.

## 출력 외 금지

- 다른 텍스트, 설명, 주석 출력 금지
- `scenarios` 와 `spec_md` 두 필드만 포함하는 JSON 블록 하나
```

- [ ] **Step 2: Commit**

```bash
git add agents/spec-author.md
git commit -m "feat(spec-author): agent persona for scenarios.json generation"
```

---

## Task 5: scripts/spec_generate.sh — GREEN

**Files:**
- Create: `scripts/spec_generate.sh`

- [ ] **Step 1: script 작성**

`scripts/spec_generate.sh`:

```bash
#!/usr/bin/env bash
# spec_generate.sh <slug>
#   - LLM 으로 scenarios.json + spec.md 생성
#   - ajv strict validate (G0 게이트)
#   - research/<slug>/spec/{scenarios.json, spec.md, runs/<ISO>/log.jsonl} 작성

set -euo pipefail

SLUG="${1:-}"
[[ -n "${SLUG}" ]] || { echo "slug required" >&2; exit 2; }
[[ -f "research/${SLUG}/README.md" ]] || { echo "missing research/${SLUG}/README.md" >&2; exit 1; }

INTENT="research/${SLUG}/intent.json"
[[ -f "${INTENT}" ]] || INTENT=""

ISO="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_DIR="research/${SLUG}/spec/runs/${ISO}"
SPEC_DIR="research/${SLUG}/spec"
mkdir -p "${RUN_DIR}" "${SPEC_DIR}"
LOG="${RUN_DIR}/log.jsonl"
log() { jq -nc --arg t "$(date -u +%FT%TZ)" --arg s "$1" --arg m "$2" '{ts:$t,stage:"spec",step:$s,msg:$m}' >> "${LOG}"; }

log start "slug=${SLUG}"

INTENT_HASH=""
INTENT_CONTENT="{}"
if [[ -n "${INTENT}" ]]; then
  INTENT_HASH=$(sha256sum "${INTENT}" | awk '{print $1}')
  INTENT_CONTENT=$(cat "${INTENT}")
fi

README_CONTENT=$(cat "research/${SLUG}/README.md")

PROMPT_INPUT=$(jq -nc \
  --arg slug "${SLUG}" \
  --arg readme "${README_CONTENT}" \
  --argjson intent "${INTENT_CONTENT}" \
  --arg intent_hash "${INTENT_HASH}" \
  --arg schema_path "tests/research-engine/schemas/scenarios.schema.json" \
  '{slug:$slug, readme:$readme, intent:$intent, intent_hash:$intent_hash, schema_path:$schema_path}')

# LLM 호출 — claude CLI 사용. spec-author persona 를 system prompt 로. input 은 prompt 본문에 첨부.
log llm.call ""
SYSTEM_PROMPT=$(cat agents/spec-author.md)
USER_PROMPT=$(printf 'spec-author: produce scenarios + spec.md from the JSON below.\n\n```json\n%s\n```' "${PROMPT_INPUT}")
LLM_OUT=$(claude -p --append-system-prompt "${SYSTEM_PROMPT}" "${USER_PROMPT}" 2>>"${RUN_DIR}/llm.stderr" || true)

# fenced JSON 블록만 추출
JSON_BLOCK=$(echo "${LLM_OUT}" | awk '/^```/{f=!f;next} f' | head -c 500000)
[[ -n "${JSON_BLOCK}" ]] || JSON_BLOCK="${LLM_OUT}"

# scenarios + spec_md 분리
SCENARIOS=$(echo "${JSON_BLOCK}" | jq '.scenarios')
SPEC_MD=$(echo "${JSON_BLOCK}" | jq -r '.spec_md')

if [[ "${SCENARIOS}" == "null" || -z "${SCENARIOS}" ]]; then
  log llm.fail "no scenarios in output"
  echo "[spec] LLM did not produce valid output. See ${RUN_DIR}/llm.stderr" >&2
  exit 1
fi

# _meta 보강 (LLM 이 누락했을 수 있음)
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
SCENARIOS=$(echo "${SCENARIOS}" | jq \
  --arg by "spec-author@${GIT_SHA}" \
  --arg at "$(date -u +%FT%TZ)" \
  --arg ih "${INTENT_HASH:-0000000000000000000000000000000000000000000000000000000000000000}" \
  '._meta = {generated_by:$by, generated_at:$at, source_intent_hash:$ih}')

echo "${SCENARIOS}" > "${SPEC_DIR}/scenarios.json"
printf '%s\n' "${SPEC_MD}" > "${SPEC_DIR}/spec.md"

# G0 게이트 — ajv strict validate
log g0.start ""
if node --input-type=module -e "
import { validateScenariosFile } from './lib/scenarios_validator.mjs';
const r = validateScenariosFile('${SPEC_DIR}/scenarios.json');
if (!r.valid) {
  console.error(JSON.stringify(r.errors, null, 2));
  process.exit(1);
}
"; then
  log g0.ok ""
else
  log g0.fail "scenarios.json failed schema validation"
  echo "[spec] G0 gate failed — see above" >&2
  exit 1
fi

log finish ok
echo "[spec] ${SPEC_DIR}/scenarios.json + spec.md — G0 PASS"
```

- [ ] **Step 2: 실행 권한**

```bash
chmod +x scripts/spec_generate.sh
```

- [ ] **Step 3: 테스트 실행 — GREEN 확인**

```bash
pnpm test:bats -- tests/research-engine/spec.test.sh
```

Expected: 5 bats tests PASS

- [ ] **Step 4: Commit GREEN**

```bash
git add scripts/spec_generate.sh
git commit -m "feat(spec): GREEN — spec_generate.sh with G0 ajv gate"
```

---

## Task 6: commands/spec.md

**Files:**
- Create: `commands/spec.md`

- [ ] **Step 1: slash command 진입 파일**

`commands/spec.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add commands/spec.md
git commit -m "feat(spec): /spec slash command entry"
```

---

## Task 7: `/design` test — RED

**Files:**
- Create: `tests/research-engine/fixtures/handoff-sample/index.html`
- Create: `tests/research-engine/fixtures/handoff-sample/meta.json`
- Create: `tests/research-engine/design.test.sh`

`/design` 의 실제 동작은 기존 `design_collect.mjs` 가 claude.ai/design 자동화로 핸드오프 받는 무거운 흐름이다. 테스트에서는 fixture 가 이미 존재하면 자동화 skip 하는 cache mode 만 검증한다.

- [ ] **Step 1: handoff fixture 작성**

`tests/research-engine/fixtures/handoff-sample/index.html`:

```html
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>fixture</title></head>
<body><h1 data-testid="landing-hero">Sample handoff</h1></body></html>
```

`tests/research-engine/fixtures/handoff-sample/meta.json`:

```json
{
  "captured_at": "2026-05-23T10:00:00.000Z",
  "source_url": "https://claude.ai/design/fixture",
  "pages": [{ "name": "landing", "html": "index.html", "assets": [] }],
  "design_system": { "tokens": {}, "components": [] }
}
```

- [ ] **Step 2: bats test 작성**

`tests/research-engine/design.test.sh`:

```bash
#!/usr/bin/env bats

setup() {
  SLUG="2026-05-23-design-test-fixture"
  TARGET="research/${SLUG}"
  mkdir -p "${TARGET}/spec" "${TARGET}/design/handoff"
  echo "# Test fixture" > "${TARGET}/README.md"
  echo "## Test spec" > "${TARGET}/spec/spec.md"
  cp tests/research-engine/fixtures/handoff-sample/index.html "${TARGET}/design/handoff/"
  cp tests/research-engine/fixtures/handoff-sample/meta.json "${TARGET}/design/handoff/"
  export RESEARCH_ENGINE_DESIGN_CACHE_ONLY=1
}

teardown() {
  rm -rf "research/2026-05-23-design-test-fixture"
}

@test "design script exists and is executable" {
  [ -x scripts/design_collect_only.sh ]
}

@test "design rejects missing slug" {
  run scripts/design_collect_only.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"slug required"* ]]
}

@test "design detects cached handoff and skips claude.ai automation" {
  run scripts/design_collect_only.sh "2026-05-23-design-test-fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"using existing handoff"* ]]
  [ -f "research/2026-05-23-design-test-fixture/design/handoff/index.html" ]
  [ -f "research/2026-05-23-design-test-fixture/design/handoff/meta.json" ]
  ls research/2026-05-23-design-test-fixture/design/runs/ | grep -q '^[0-9]'
}
```

- [ ] **Step 3: 권한 + 테스트 실행 — RED 확인**

```bash
chmod +x tests/research-engine/design.test.sh
bats tests/research-engine/design.test.sh
```

Expected: FAIL — `not executable: scripts/design_collect_only.sh`

- [ ] **Step 4: Commit RED**

```bash
git add tests/research-engine/fixtures/handoff-sample tests/research-engine/design.test.sh
git commit -m "test(design): RED — /design cache-mode bats test + handoff fixture"
```

---

## Task 8: scripts/design_collect_only.sh — GREEN

**Files:**
- Create: `scripts/design_collect_only.sh`

- [ ] **Step 1: script 작성**

`scripts/design_collect_only.sh`:

```bash
#!/usr/bin/env bash
# design_collect_only.sh <slug> [--from-url <handoff-api-url>] [--fresh] [--login-headful]
#   - claude.ai/design 핸드오프만 받아온다 (build/deploy 분리됨)
#   - 기존 design/handoff/index.html + meta.json 존재시 skip (cache mode)

set -euo pipefail

SLUG=""
FROM_URL=""
FRESH=0
LOGIN_HEADFUL=0
i=1
for a in "$@"; do
  case "$a" in
    --fresh) FRESH=1 ;;
    --login-headful) LOGIN_HEADFUL=1 ;;
    --from-url) FROM_URL="${!((i+1))}" ;;
    --from-url=*) FROM_URL="${a#--from-url=}" ;;
    --*) ;;
    *) [[ -z "${SLUG}" && "$a" != http* ]] && SLUG="$a" ;;
  esac
  i=$((i+1))
done

[[ -n "${SLUG}" ]] || { echo "slug required" >&2; exit 2; }
[[ -f "research/${SLUG}/README.md" ]] || { echo "missing research/${SLUG}/README.md" >&2; exit 1; }

ISO="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_DIR="research/${SLUG}/design/runs/${ISO}"
DESIGN_DIR="research/${SLUG}/design"
mkdir -p "${RUN_DIR}"
LOG="${RUN_DIR}/log.jsonl"
log() { jq -nc --arg t "$(date -u +%FT%TZ)" --arg s "$1" --arg m "$2" '{ts:$t,stage:"design",step:$s,msg:$m}' >> "${LOG}"; }

# spec/scenarios.json 의 _meta.source_intent_hash 가 현재 intent.json 과 다르면 경고 (자동 재실행 안 함)
if [[ -f "research/${SLUG}/spec/scenarios.json" && -f "research/${SLUG}/intent.json" ]]; then
  STORED=$(jq -r '._meta.source_intent_hash // ""' "research/${SLUG}/spec/scenarios.json")
  CURRENT=$(sha256sum "research/${SLUG}/intent.json" | awk '{print $1}')
  if [[ -n "${STORED}" && "${STORED}" != "${CURRENT}" ]]; then
    echo "[design] WARN: spec/scenarios.json 의 source_intent_hash 가 현재 intent.json 과 다름. /spec 재실행 권장." >&2
    log spec.stale ""
  fi
fi

log start "slug=${SLUG}"

# Cache mode — 기존 handoff 존재시 skip
if [[ "${FRESH}" == "0" && -f "${DESIGN_DIR}/handoff/index.html" && -f "${DESIGN_DIR}/handoff/meta.json" ]]; then
  log collect.cached "using existing handoff/"
  echo "[design] using existing handoff/ — skip claude.ai automation"
  log finish ok
  exit 0
fi

# 테스트 환경에서 cache 강제 — 실제 자동화 시도 차단
if [[ "${RESEARCH_ENGINE_DESIGN_CACHE_ONLY:-0}" == "1" ]]; then
  echo "[design] cache-only mode requested but no cached handoff found" >&2
  log fail "no cache in cache-only mode"
  exit 1
fi

# 실제 자동화 — 기존 design_collect.mjs 재사용
log collect.start ""
ARGS=("${SLUG}")
[[ "${FRESH}" == "1" ]] && ARGS+=("--fresh")
[[ "${LOGIN_HEADFUL}" == "1" ]] && ARGS+=("--login-headful")
[[ -n "${FROM_URL}" ]] && ARGS+=("--from-url" "${FROM_URL}")

set +e
node scripts/design_collect.mjs "${ARGS[@]}" 2>&1 | tee -a "${RUN_DIR}/collect.log"
RC=${PIPESTATUS[0]}
set -e

if [[ "${RC}" == "11" ]]; then
  log collect.manual "design_collect printed manual prompt — pipeline halted"
  echo "[design] 수동 진행 필요. 위 안내대로 claude.ai/design 사용 후" >&2
  echo "[design]   bash scripts/design_collect_only.sh ${SLUG} --from-url <URL>" >&2
  echo "[design] 재실행." >&2
  exit 11
fi

if [[ "${RC}" != "0" ]]; then
  log collect.fail "exit ${RC}"
  exit "${RC}"
fi

log finish ok
echo "[design] ${DESIGN_DIR}/handoff/ — collected"
```

- [ ] **Step 2: 실행 권한**

```bash
chmod +x scripts/design_collect_only.sh
```

- [ ] **Step 3: 테스트 실행 — GREEN 확인**

```bash
bats tests/research-engine/design.test.sh
```

Expected: 3 bats tests PASS

- [ ] **Step 4: Commit GREEN**

```bash
git add scripts/design_collect_only.sh
git commit -m "feat(design): GREEN — design_collect_only.sh with cache mode + spec staleness warning"
```

---

## Task 9: commands/design.md — rewrite (scope-reduced)

**Files:**
- Modify: replace `commands/research-design.md` with new `commands/design.md`

- [ ] **Step 1: 기존 파일 삭제 + 새 파일 작성**

```bash
git rm commands/research-design.md
```

`commands/design.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add commands/design.md
git commit -m "feat(design): /design slash — rewrite of /research-design with scope reduced to handoff-only"
```

---

## Task 10: `/deploy` e2e infrastructure (G3 generic runner)

**Files:**
- Create: `tests/research-engine/e2e/playwright.config.ts`
- Create: `tests/research-engine/e2e/scenarios.spec.ts`

G3 게이트는 prod URL 대상으로 scenarios.json 의 시나리오를 돌린다. 기존 `tests/research-design/e2e/runner.ts` 의 `runScenarios()` 를 import 해서 재사용 (DRY).

- [ ] **Step 1: playwright config**

`tests/research-engine/e2e/playwright.config.ts`:

```typescript
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  fullyParallel: false,
  retries: 0,
  reporter: [['list'], ['json', { outputFile: 'test-results/research-engine-e2e.json' }]],
  use: {
    baseURL: process.env.E2E_BASE_URL || 'http://localhost:3000',
    headless: true,
    trace: 'retain-on-failure',
    video: 'retain-on-failure'
  }
});
```

- [ ] **Step 2: generic scenarios spec — env-driven**

`tests/research-engine/e2e/scenarios.spec.ts`:

```typescript
import { runScenarios } from '../../research-design/e2e/runner';

const path = process.env.E2E_SCENARIOS_PATH;
if (!path) {
  throw new Error('E2E_SCENARIOS_PATH env var required');
}
runScenarios(path);
```

- [ ] **Step 3: package.json 에 test:e2e:re script 추가**

`package.json` 의 scripts 에 추가:

```json
"test:e2e:re": "playwright test --config tests/research-engine/e2e/playwright.config.ts"
```

- [ ] **Step 4: Commit**

```bash
git add tests/research-engine/e2e package.json
git commit -m "feat(deploy): e2e infrastructure for G3 — env-driven scenarios runner"
```

---

## Task 11: `/deploy` test — RED

**Files:**
- Create: `tests/research-engine/mock-bin/ssh`
- Create: `tests/research-engine/mock-bin/scp`
- Create: `tests/research-engine/fixtures/app-sample/package.json`
- Create: `tests/research-engine/deploy.test.sh`

LXC 배포는 실제 hetzner 호출이라 테스트에서 ssh/scp 를 mock 해야 한다.

- [ ] **Step 1: ssh / scp mock**

`tests/research-engine/mock-bin/ssh`:

```bash
#!/usr/bin/env bash
# Mock ssh — emits canned responses for /deploy tests
case "$*" in
  *"pct list"*) echo "100 stopped rd-mock";;
  *"pvesh get /cluster/nextid"*) echo "101";;
  *"tailscale status"*) echo "mock-tailnet-1.2.3.4 mock-host idle";;
  *) echo "[mock-ssh] cmd: $*" >&2;;
esac
exit 0
```

`tests/research-engine/mock-bin/scp`:

```bash
#!/usr/bin/env bash
echo "[mock-scp] $*" >&2
exit 0
```

```bash
chmod +x tests/research-engine/mock-bin/ssh tests/research-engine/mock-bin/scp
```

- [ ] **Step 2: app fixture**

`tests/research-engine/fixtures/app-sample/package.json`:

```json
{
  "name": "app-sample",
  "private": true,
  "scripts": {
    "build": "echo 'mock build'",
    "start": "node -e \"require('http').createServer((q,r)=>{r.writeHead(200);r.end('ok')}).listen(3000)\""
  },
  "engines": { "node": "22" }
}
```

- [ ] **Step 3: bats test**

`tests/research-engine/deploy.test.sh`:

```bash
#!/usr/bin/env bats

setup() {
  export PATH="$(pwd)/tests/research-engine/mock-bin:$PATH"
  export RESEARCH_ENGINE_DEPLOY_MOCK=1
  SLUG="2026-05-23-deploy-test-fixture"
  TARGET="research/${SLUG}"
  mkdir -p "${TARGET}/spec" "${TARGET}/app"
  echo "# Test" > "${TARGET}/README.md"
  cp tests/research-engine/fixtures/scenarios-valid.json "${TARGET}/spec/scenarios.json"
  cp tests/research-engine/fixtures/app-sample/package.json "${TARGET}/app/package.json"
  export HETZNER_MASTER_HOST=mock-host
  export HETZNER_MASTER_USER=mock-user
}

teardown() {
  rm -rf "research/2026-05-23-deploy-test-fixture"
}

@test "deploy dispatch exists and is executable" {
  [ -x scripts/deploy_dispatch.sh ]
}

@test "deploy rejects missing slug" {
  run scripts/deploy_dispatch.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"slug required"* ]]
}

@test "deploy rejects missing app/" {
  rm -rf "research/2026-05-23-deploy-test-fixture/app"
  run scripts/deploy_dispatch.sh "2026-05-23-deploy-test-fixture"
  [ "$status" -ne 0 ]
  [[ "$output" == *"app"* ]]
}

@test "deploy in mock mode produces deploy.json with mock host" {
  run scripts/deploy_dispatch.sh "2026-05-23-deploy-test-fixture"
  [ "$status" -eq 0 ]
  [ -f "research/2026-05-23-deploy-test-fixture/deploy/deploy.json" ]
  jq -e '.target == "lxc"' "research/2026-05-23-deploy-test-fixture/deploy/deploy.json"
  jq -e '.host | length > 0' "research/2026-05-23-deploy-test-fixture/deploy/deploy.json"
}

@test "deploy writes runs/<ISO>/log.jsonl with stage=deploy" {
  scripts/deploy_dispatch.sh "2026-05-23-deploy-test-fixture"
  RUN=$(ls research/2026-05-23-deploy-test-fixture/deploy/runs/ | head -1)
  [ -n "${RUN}" ]
  grep -q '"stage":"deploy"' "research/2026-05-23-deploy-test-fixture/deploy/runs/${RUN}/log.jsonl"
}
```

- [ ] **Step 4: 권한 + RED 확인**

```bash
chmod +x tests/research-engine/deploy.test.sh
bats tests/research-engine/deploy.test.sh
```

Expected: FAIL — `not executable: scripts/deploy_dispatch.sh`

- [ ] **Step 5: Commit RED**

```bash
git add tests/research-engine/mock-bin/ssh tests/research-engine/mock-bin/scp tests/research-engine/fixtures/app-sample tests/research-engine/deploy.test.sh
git commit -m "test(deploy): RED — /deploy bats test + ssh/scp mocks + app fixture"
```

---

## Task 12: scripts/deploy_lxc.sh — rename (no functional change yet)

**Files:**
- Rename: `scripts/lxc_deploy.sh` → `scripts/deploy_lxc.sh`

- [ ] **Step 1: git mv**

```bash
git mv scripts/lxc_deploy.sh scripts/deploy_lxc.sh
```

- [ ] **Step 2: Commit**

```bash
git commit -m "refactor(deploy): rename lxc_deploy.sh → deploy_lxc.sh"
```

---

## Task 13: agents/deploy-planner.md

**Files:**
- Create: `agents/deploy-planner.md`

- [ ] **Step 1: agent persona**

`agents/deploy-planner.md`:

```markdown
---
name: deploy-planner
description: research/<slug>/app/ 의 package.json 등을 분석해 hetzner LXC 사양 (cores, memory, build/start 명령 등) 을 추론하는 LLM persona. hetzner-master GitHub repo 의 LXC template convention 을 준수.
---

# deploy-planner

## 너의 역할

너는 research-engine 파이프라인의 **deploy planner** 다. 너의 산출물은 `/deploy` 의 LXC adapter (`scripts/deploy_lxc.sh`) 가 컨테이너 생성·앱 빌드·systemd unit 작성 시 참조할 `lxc_config.json` 이다.

## 입력 (prompt 본문 안에 첨부된 JSON 블록 — fenced ```json)

```json
{
  "slug": "<slug>",
  "package_json": { ... research/<slug>/app/package.json 전체 ... },
  "deploy_hints": { ... .deploy-hints.json 내용 (있으면) ... } | null,
  "hetzner_master_conventions": "<gprecious/hetzner-master 의 LXC template README 텍스트 (있으면)>"
}
```

## 산출물 (stdout, fenced JSON 블록 한 개)

```json
{
  "container_name": "rd-<slug 의 alphanum-only, max 63>",
  "image": "local:vztmpl/debian-12-standard_*.tar.zst",
  "cores": 1,
  "memory_mb": 1024,
  "disk_gb": 10,
  "runtime": "node@22",
  "package_manager": "pnpm",
  "build_cmd": "pnpm build",
  "start_cmd": "pnpm start",
  "port": 3000,
  "static_only": false,
  "env_keys": ["DATABASE_URL"],
  "systemd_unit_name": "research-engine-app.service"
}
```

## 추론 규칙 (deploy_hints 가 있으면 우선, 없으면 package_json 에서):

1. `runtime`: deploy_hints.runtime → package_json.engines.node 의 "22" → 기본 "node@22"
2. `package_manager`: deploy_hints.package_manager → package_json.packageManager 의 prefix → 기본 "pnpm"
3. `build_cmd`: deploy_hints.build_cmd → "${pm} build"
4. `start_cmd`: deploy_hints.start_cmd → "${pm} start"
5. `port`: deploy_hints.port → 기본 3000
6. `static_only`: deploy_hints.static_only → next/vite/react-scripts 의존성 없을 때 true → 기본 false
7. `memory_mb`: deploy_hints.estimated_ram_mb ≤ 512 면 1024, ≤ 1024 면 2048, 그 이상 4096
8. `cores`: memory_mb ≤ 2048 → 1, 그 이상 → 2
9. `disk_gb`: 기본 10
10. `env_keys`: deploy_hints.env_keys 만. package_json 에서 추론 안 함
11. `image`: hetzner_master_conventions 에 명시된 template 우선. 없으면 debian-12 default
12. `container_name`: "rd-${slug//[^a-z0-9]/-}".slice(0, 63)

## 출력 외 금지

JSON 블록 한 개만. 설명·주석 금지.
```

- [ ] **Step 2: Commit**

```bash
git add agents/deploy-planner.md
git commit -m "feat(deploy-planner): agent persona for LXC config inference"
```

---

## Task 14: scripts/deploy_dispatch.sh — GREEN

**Files:**
- Create: `scripts/deploy_dispatch.sh`

- [ ] **Step 1: dispatch script 작성**

`scripts/deploy_dispatch.sh`:

```bash
#!/usr/bin/env bash
# deploy_dispatch.sh <slug> [--target lxc]
#   - app/ 검증 → deploy-planner agent 로 lxc_config.json 생성 → deploy_lxc.sh 호출 → G3 e2e

set -euo pipefail

SLUG=""
TARGET="lxc"
i=1
for a in "$@"; do
  case "$a" in
    --target) TARGET="${!((i+1))}" ;;
    --target=*) TARGET="${a#--target=}" ;;
    --*) ;;
    *) [[ -z "${SLUG}" ]] && SLUG="$a" ;;
  esac
  i=$((i+1))
done

[[ -n "${SLUG}" ]] || { echo "slug required" >&2; exit 2; }
[[ -d "research/${SLUG}/app" ]] || { echo "missing research/${SLUG}/app/ — 사용자 build 필요" >&2; exit 1; }
[[ -f "research/${SLUG}/app/package.json" ]] || { echo "missing research/${SLUG}/app/package.json" >&2; exit 1; }
[[ -f "research/${SLUG}/spec/scenarios.json" ]] || { echo "missing research/${SLUG}/spec/scenarios.json — /spec 실행 필요" >&2; exit 1; }

ISO="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_DIR="research/${SLUG}/deploy/runs/${ISO}"
DEPLOY_DIR="research/${SLUG}/deploy"
mkdir -p "${RUN_DIR}" "${DEPLOY_DIR}"
LOG="${RUN_DIR}/log.jsonl"
log() { jq -nc --arg t "$(date -u +%FT%TZ)" --arg s "$1" --arg m "$2" '{ts:$t,stage:"deploy",step:$s,msg:$m}' >> "${LOG}"; }

# spec staleness 경고
if [[ -f "research/${SLUG}/intent.json" ]]; then
  STORED=$(jq -r '._meta.source_intent_hash // ""' "research/${SLUG}/spec/scenarios.json")
  CURRENT=$(sha256sum "research/${SLUG}/intent.json" | awk '{print $1}')
  if [[ -n "${STORED}" && "${STORED}" != "${CURRENT}" ]]; then
    echo "[deploy] WARN: spec stale — /spec 재실행 권장" >&2
    log spec.stale ""
  fi
fi

log start "slug=${SLUG} target=${TARGET}"

# deploy-planner agent 로 lxc_config.json 생성
log planner.start ""
HINTS="{}"
[[ -f "research/${SLUG}/app/.deploy-hints.json" ]] && HINTS=$(cat "research/${SLUG}/app/.deploy-hints.json")
PKG=$(cat "research/${SLUG}/app/package.json")
HMC=""  # hetzner_master_conventions — 향후 git clone 캐시에서 읽음. 이번 작업에선 빈 문자열.

PLANNER_INPUT=$(jq -nc \
  --arg slug "${SLUG}" \
  --argjson pkg "${PKG}" \
  --argjson hints "${HINTS}" \
  --arg hmc "${HMC}" \
  '{slug:$slug, package_json:$pkg, deploy_hints:$hints, hetzner_master_conventions:$hmc}')

if [[ "${RESEARCH_ENGINE_DEPLOY_MOCK:-0}" == "1" ]]; then
  # Mock mode — LLM 호출 skip, deterministic config
  LXC_CONFIG=$(jq -nc --arg slug "${SLUG}" '{
    container_name: ("rd-" + ($slug | gsub("[^a-z0-9]"; "-")) | .[0:63]),
    image: "local:vztmpl/debian-12-standard_*.tar.zst",
    cores: 1, memory_mb: 1024, disk_gb: 10,
    runtime: "node@22", package_manager: "pnpm",
    build_cmd: "pnpm build", start_cmd: "pnpm start",
    port: 3000, static_only: false, env_keys: [],
    systemd_unit_name: "research-engine-app.service"
  }')
else
  SYSTEM_PROMPT=$(cat agents/deploy-planner.md)
  USER_PROMPT=$(printf 'deploy-planner: emit lxc_config.json from the JSON below.\n\n```json\n%s\n```' "${PLANNER_INPUT}")
  PLANNER_OUT=$(claude -p --append-system-prompt "${SYSTEM_PROMPT}" "${USER_PROMPT}" 2>>"${RUN_DIR}/planner.stderr" || true)
  LXC_CONFIG=$(echo "${PLANNER_OUT}" | awk '/^```/{f=!f;next} f' | head -c 100000)
  [[ -n "${LXC_CONFIG}" ]] || LXC_CONFIG="${PLANNER_OUT}"
fi

echo "${LXC_CONFIG}" > "${RUN_DIR}/lxc_config.json"
log planner.done ""

if [[ "${TARGET}" != "lxc" ]]; then
  log fail "unsupported target=${TARGET}"
  echo "[deploy] only --target=lxc supported in this scope" >&2
  exit 1
fi

# 이전 host 보존 (rollback 용)
PREV_HOST=""
[[ -f "${DEPLOY_DIR}/deploy.json" ]] && PREV_HOST=$(jq -r '.host // ""' "${DEPLOY_DIR}/deploy.json")

# LXC 배포
log lxc.start ""
if [[ "${RESEARCH_ENGINE_DEPLOY_MOCK:-0}" == "1" ]]; then
  HOST="mock-${SLUG}.ts.net"
  LXC_ID=999
  log lxc.mock "host=${HOST}"
else
  set +e
  HOST=$(bash scripts/deploy_lxc.sh "${SLUG}" "research/${SLUG}/app" "${RUN_DIR}/lxc_config.json" 2>>"${RUN_DIR}/adapter.log")
  RC=$?
  set -e
  if [[ "${RC}" != "0" ]]; then
    log lxc.fail "exit ${RC}"
    echo "[deploy] LXC 배포 실패 — see ${RUN_DIR}/adapter.log" >&2
    exit 4
  fi
  LXC_ID=$(grep -oP 'CTID=\K[0-9]+' "${RUN_DIR}/adapter.log" | tail -1 || echo "0")
fi
log lxc.done "host=${HOST}"

# G3 게이트 — prod URL 대상 e2e
log g3.start "baseUrl=https://${HOST}"
G3_PASSED=0
if [[ "${RESEARCH_ENGINE_DEPLOY_MOCK:-0}" == "1" ]]; then
  G3_PASSED=1
  jq -n --arg host "${HOST}" '{mock:true, host:$host, passed:true}' > "${RUN_DIR}/gate-3.json"
else
  set +e
  E2E_BASE_URL="https://${HOST}" \
  E2E_SCENARIOS_PATH="research/${SLUG}/spec/scenarios.json" \
    pnpm test:e2e:re --reporter=json > "${RUN_DIR}/gate-3.json" 2>>"${RUN_DIR}/g3.stderr"
  RC=$?
  set -e
  [[ "${RC}" == "0" ]] && G3_PASSED=1
fi

if [[ "${G3_PASSED}" == "0" ]]; then
  log g3.fail ""
  # NOTE: LXC 는 slug-idempotent — 새 배포가 기존 컨테이너를 in-place 갱신. 자동 롤백은 v1 scope 밖.
  # prev_host 는 deploy.json 에 보존되어 사용자 수동 revert 가능. 향후 별도 task.
  echo "[deploy] G3 e2e 실패 — see ${RUN_DIR}/gate-3.json" >&2
  echo "[deploy] (자동 롤백 없음 — 필요시 prev_host=${PREV_HOST} 로 수동 revert)" >&2
  exit 4
fi
log g3.ok ""

# deploy.json 작성
jq -n \
  --arg target "${TARGET}" \
  --arg host "${HOST}" \
  --argjson lxc_id "${LXC_ID}" \
  --arg deployed_at "$(date -u +%FT%TZ)" \
  --arg prev_host "${PREV_HOST}" \
  --arg report "runs/${ISO}/gate-3.json" \
  '{target:$target, host:$host, lxc_id:$lxc_id, deployed_at:$deployed_at, prev_host:$prev_host, g3:{passed:true, report:$report}}' \
  > "${DEPLOY_DIR}/deploy.json"

log finish ok
echo "[deploy] host=${HOST} — G3 PASS"
echo "${HOST}"
```

- [ ] **Step 2: 실행 권한**

```bash
chmod +x scripts/deploy_dispatch.sh
```

- [ ] **Step 3: 테스트 실행 — GREEN 확인**

```bash
bats tests/research-engine/deploy.test.sh
```

Expected: 5 bats tests PASS

- [ ] **Step 4: Commit GREEN**

```bash
git add scripts/deploy_dispatch.sh
git commit -m "feat(deploy): GREEN — deploy_dispatch.sh with deploy-planner + LXC + G3 + auto-rollback hook"
```

---

## Task 15: commands/deploy.md

**Files:**
- Create: `commands/deploy.md`

- [ ] **Step 1: slash command**

`commands/deploy.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add commands/deploy.md
git commit -m "feat(deploy): /deploy slash command entry"
```

---

## Task 16: Migration cleanup — 기존 파일 제거

**Files:**
- Delete: `scripts/research_design_pipeline.sh`
- Delete: `tests/research-design/pipeline.test.sh`

- [ ] **Step 1: 기존 pipeline 스크립트 삭제**

```bash
git rm scripts/research_design_pipeline.sh
git rm tests/research-design/pipeline.test.sh
```

- [ ] **Step 2: package.json 의 test:bats 가 신경로만 가리키는지 확인**

`package.json` 의 `test:bats` 가 이미 Task 3 에서 `tests/research-engine/*.test.sh` 로 갱신됐는지 grep:

```bash
grep '"test:bats"' package.json
```

Expected: `"test:bats": "bats tests/research-engine/spec.test.sh tests/research-engine/design.test.sh tests/research-engine/deploy.test.sh"`

- [ ] **Step 3: 전체 테스트 실행**

```bash
pnpm test:unit && pnpm test:bats
```

Expected: 모든 vitest + bats PASS

- [ ] **Step 4: Commit cleanup**

```bash
git add -u
git commit -m "chore: remove deprecated research_design_pipeline.sh + old pipeline.test.sh"
```

---

## Task 17: End-to-end manual 검증 체크리스트

**Files:** 없음 (수동 검증)

이 task 는 자동화 테스트 아님 — 사용자가 직접 시드 슬러그로 전체 흐름을 한 번 돌려 검증한다.

- [ ] **Step 1: 시드 슬러그 준비**

```bash
ls research/2026-05-22-ai-image-vectorization-service/
```

`README.md` 존재 확인.

- [ ] **Step 2: `/spec` 실행 (수동)**

Claude Code 에서:

```
/spec 2026-05-22-ai-image-vectorization-service
```

확인:
- `research/<slug>/spec/scenarios.json` 생성
- `research/<slug>/spec/spec.md` 생성
- G0 PASS 메시지 stdout

- [ ] **Step 3: `/design` 실행 (수동)**

기존 `design/handoff/` 가 이미 있으므로 cache mode 로 즉시 종료해야 함.

```
/design 2026-05-22-ai-image-vectorization-service
```

확인:
- `using existing handoff/` 메시지
- `design/runs/<ISO>/log.jsonl` 추가 생성

- [ ] **Step 4: `app/` 수동 작성 (외부 툴 사용)**

`research/2026-05-22-ai-image-vectorization-service/app/` 에 Next.js 앱 작성. 최소 요구:
- `package.json` (build/start script)
- `/health` endpoint (200 응답)
- scenarios.json 의 testid 셀렉터 모두 존재

- [ ] **Step 5: `/deploy` 실행 (수동)**

```
/deploy 2026-05-22-ai-image-vectorization-service
```

확인:
- `deploy/deploy.json` 의 `host` 가 reachable
- `deploy/runs/<ISO>/gate-3.json` 의 모든 시나리오 PASS
- Tailscale hostname 으로 브라우저 접근 가능

- [ ] **Step 6: 검증 결과 기록**

`research/<slug>/deploy/README.md` 에 한 줄 — 배포 일시 + host URL.

- [ ] **Step 7: Final commit (검증 완료 marker)**

```bash
git commit --allow-empty -m "verify: end-to-end manual check passed for seed slug"
```
