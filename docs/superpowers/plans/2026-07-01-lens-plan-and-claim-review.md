# Lens Plan + Claim Review Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two optional STORM-inspired layers to `/research` — a **lens plan** (perspective-guided question planning before adapter dispatch) and a **claim review** (contradiction / evidence-reliability / missing-lens review before README synthesis) — without replacing research-engine's source-adapter architecture or forcing fixed personas.

**Architecture:** Keep the existing 5-stage `/research` pipeline. Insert **Stage 3.5 — Lens Plan** (gated ON only for broad/ambiguous inputs) that a new `lens-planner` subagent fills into `research/<slug>/lens_plan.json`; thread its questions/queries into Stage 4 adapter prompts as *hints only* (adapters stay source-oriented). Insert **Stage 4.6 — Claim Review** (gated) that a new `claim-reviewer` subagent fills into `research/<slug>/claim_review.json`, folding contradiction map + evidence reliability + missing-lens detection into one central reviewer. Report gets two optional sections (`## 검증 매트릭스`, `## 누락 관점 / 후속 질문`). Gating is deterministic (bash scripts), artifact shapes are Ajv-validated (vitest), and both new agents carry `<!-- evolvable:… -->` regions so `/evolve` mutates/benches them exactly like adapters.

**Tech Stack:**
- Claude Code / Codex plugin format (`commands/*.md`, `agents/*.md`, `scripts/*.sh`, `lib/*.mjs`)
- Bash 5 (+ `jq`) for deterministic gating utilities
- `ajv` 2020 + `ajv-formats` for JSON artifact validation (matches `lib/scenarios_validator.mjs`)
- `vitest` for validator unit tests, `bats-core` for shell + command-doc structural tests
- Generic `/evolve` harness (`scripts/evolve_run.sh` + `lib/evolve/*.mjs`) — already name-agnostic, works on any `agents/<name>.md` with evolvable regions

**Source of this plan:** `research/2026-06-30-stanford-storm-research-engine-upgrade/README.md` (STORM video validation — the "채택 판정" table and "제안 구현안" section). Do NOT re-research STORM.

---

## Design decisions (LOCKED contracts — implement exactly)

### Artifact 1 — `research/<slug>/lens_plan.json`

Written by Stage 3.5 when the lens gate is ON. When the gate is OFF the file is **not created** (Stage 4 treats absence as no-op). A `generated:false` sentinel is *allowed* by the schema but not required.

```json
{
  "slug": "2026-07-01-voice-ai-agents",
  "input_type": "topic",
  "generated": true,
  "gate_reason": "topic-mode",
  "created": "2026-07-01T12:00:00Z",
  "lenses": [
    {
      "lens_id": "practitioner",
      "title": "현업 실무자 관점",
      "rationale": "실제 배포·운영에서 드러나는 제약을 다른 관점이 놓치기 쉽다",
      "questions": ["프로덕션에서 가장 흔한 실패 모드는?", "지연/비용 트레이드오프는?"],
      "search_queries": ["voice ai agent production latency", "voice agent cost per minute"],
      "expected_blind_spots": ["학술 벤치마크가 실제 통화 품질을 대변하지 못함"]
    },
    {
      "lens_id": "skeptic",
      "title": "회의론자 관점",
      "rationale": "과대광고와 재현 불가한 데모를 걸러낸다",
      "questions": ["독립 재현된 결과가 있나?"],
      "search_queries": ["voice ai agent limitations criticism"],
      "expected_blind_spots": ["벤더 데모 편향"]
    }
  ]
}
```

Rules: `generated:true` ⇒ `lenses` has **≥2** entries; `generated:false` ⇒ `lenses` is **empty**. `gate_reason ∈ {topic-mode, weak-preview, forced, disabled-narrow-input, disabled-flag}` (must match `scripts/lens_gate.sh` output exactly).

### Artifact 2 — `research/<slug>/claim_review.json`

Written by Stage 4.6 when the claim-review gate is ON. Absent = no-op. Folds contradiction map + evidence reliability + missing-lens detector into one artifact.

```json
{
  "slug": "2026-07-01-voice-ai-agents",
  "reviewed": true,
  "created": "2026-07-01T12:00:00Z",
  "claims": [
    {
      "claim": "STORM은 oRAG 대비 Organization ≥4 비율이 25%p 높다",
      "supporting_sources": [2],
      "challenging_sources": [],
      "citation_status": "supported",
      "confidence": "high",
      "corrected_text": null,
      "needs_followup": false
    },
    {
      "claim": "STORM skill이 Claude Deep Research보다 항상 우수하다",
      "supporting_sources": [1],
      "challenging_sources": [1],
      "citation_status": "partial",
      "confidence": "low",
      "corrected_text": "단일 데모 비교이며 독립 벤치마크로 일반화되지 않는다",
      "needs_followup": true
    }
  ],
  "missing_lenses": [
    {"lens": "고객/최종 사용자 관점", "why": "owner 관점 결과만 있어 실제 사용자 체감이 빠짐", "followup_query": "voice ai agent end-user satisfaction study"}
  ]
}
```

Rules: `reviewed:false` ⇒ `claims` empty. `citation_status ∈ {supported, partial, unsupported, contradicted}`. `confidence ∈ {high, medium, low}`. `corrected_text` is string or null. Source references are **1-indexed integers** into the final `sources.json` list.

### Gating (deterministic — `scripts/*.sh`, NOT model judgment)

**Lens gate** (`scripts/lens_gate.sh <input_type> <preview_status> [--lens|--no-lens]`):
- `--no-lens` → off / `disabled-flag`
- `--lens` → on / `forced`
- `input_type == topic` → on / `topic-mode`
- `preview_status ∈ {failed, weak}` → on / `weak-preview`
- else → off / `disabled-narrow-input`

**Claim-review gate** (`scripts/claim_review_gate.sh <source_count> <lens_generated:true|false> [--review|--no-review]`):
- `--no-review` → off / `disabled-flag`
- `--review` → on / `forced`
- `source_count < 2` → off / `too-few-sources`
- `lens_generated == true` → on / `lens-planned`
- `source_count >= 4` → on / `multi-source`
- else → off / `narrow-single-lens`

### Report sections (optional — `lib/report_sections.md`)

Insert only when the corresponding artifact exists and is non-empty. Citation rule unchanged (every claim row still carries `[n]`).
- **`## 검증 매트릭스`** — table from `claim_review.claims` (주장 / 근거 / 반증 / 상태 / 신뢰도 + corrected note). Placed after §4 상세 분석.
- **`## 누락 관점 / 후속 질문`** — bullets from `claim_review.missing_lenses` + claims with `needs_followup:true`. Placed after §7 한계.

### /evolve integration

`scripts/evolve_run.sh` + `lib/evolve/prepare.mjs` are name-agnostic (verified: they take `agents/<name>.md` + region-id, no adapter allowlist). So the ONLY evolve work is: (a) give the two new agents `<!-- evolvable:… -->` regions, (b) a bats test proving `prepare`/`apply` work on them, (c) document them as eligible targets in `commands/evolve.md`. `agents/prompt-mutator.md` needs no change.

### Versioning / distribution

- research-engine is a **single tree with two manifests**. Bump BOTH `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` 0.20.1 → **0.21.0** (minor: additive feature) in lockstep.
- research-engine is a **URL source** in `gprecious-marketplace` (no pinned version there) → **no marketplace-repo change**; `git push origin main` on this repo is what propagates.
- Final step MUST `git push origin main` (shared remote) after `gh auth status` shows the `gprecious` account.

### Out of scope (do NOT build now)

HTML briefing as default output; Notion toggles for the new artifacts; wiki ingestion of lens/claim data; `/research-followup` auto-consuming `missing_lenses`; full interactive agent-team debate; fixed 5-persona forcing.

---

## File Structure (locked before task decomposition)

```
research-engine/
  commands/
    research.md                 # MODIFY: + Stage 3.5, Stage 4 lens_hints, Stage 4.6
    evolve.md                   # MODIFY: document lens-planner / claim-reviewer as targets
  agents/
    lens-planner.md             # CREATE: perspective/question planner (2 evolvable regions)
    claim-reviewer.md           # CREATE: contradiction + missing-lens reviewer (2 evolvable regions)
  scripts/
    lens_gate.sh                # CREATE: deterministic lens gate
    claim_review_gate.sh        # CREATE: deterministic claim-review gate
  lib/
    lens_plan_validator.mjs     # CREATE: Ajv validator + CLI (mirrors scenarios_validator.mjs)
    lens_plan_validator.test.mjs        # CREATE: vitest
    claim_review_validator.mjs          # CREATE
    claim_review_validator.test.mjs     # CREATE
    report_sections.md          # MODIFY: + 검증 매트릭스, 누락 관점 optional sections
  tests/research-engine/
    schemas/
      lens_plan.schema.json     # CREATE
      claim_review.schema.json  # CREATE
    fixtures/
      lens_plan-valid.json          # CREATE
      lens_plan-noop.json           # CREATE (generated:false)
      lens_plan-missing-field.json  # CREATE
      lens_plan-bad-count.json      # CREATE (generated:true but 1 lens)
      claim_review-valid.json       # CREATE
      claim_review-noop.json        # CREATE (reviewed:false)
      claim_review-missing-field.json  # CREATE
    lens_gate.test.sh           # CREATE: bats
    claim_review_gate.test.sh   # CREATE: bats
    lens-claim-agents.test.sh   # CREATE: bats (agent frontmatter + evolvable regions)
    lens-claim-pipeline.test.sh # CREATE: bats (research.md + report_sections.md wiring)
    evolve-lens-claim.test.sh   # CREATE: bats (prepare/apply on new agents)
  package.json                  # MODIFY: register new bats files in test:bats
  DEVELOPMENT.md                # MODIFY: list new tests
  README.md                     # MODIFY: mention lens plan + claim review + new sections
  CHANGELOG.md                  # MODIFY: 0.21.0 entry
  .claude-plugin/plugin.json    # MODIFY: version 0.21.0
  .codex-plugin/plugin.json     # MODIFY: version 0.21.0
```

Validators live in `lib/` so `pnpm test:unit` (`vitest run lib …`) auto-discovers `lib/*_validator.test.mjs`.

---

## Task 1: lens_plan schema + validator (vitest, TDD)

**Files:**
- Create: `tests/research-engine/schemas/lens_plan.schema.json`
- Create: `tests/research-engine/fixtures/lens_plan-valid.json`, `lens_plan-noop.json`, `lens_plan-missing-field.json`, `lens_plan-bad-count.json`
- Create: `lib/lens_plan_validator.mjs`
- Test: `lib/lens_plan_validator.test.mjs`

**Step 1: Write the schema**

`tests/research-engine/schemas/lens_plan.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://gprecious/research-engine/schemas/lens_plan.json",
  "title": "research-engine lens plan",
  "type": "object",
  "required": ["slug", "generated", "gate_reason", "lenses"],
  "additionalProperties": false,
  "properties": {
    "$schema": { "type": "string" },
    "slug": { "type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}-.+$" },
    "input_type": { "type": "string" },
    "generated": { "type": "boolean" },
    "gate_reason": {
      "type": "string",
      "enum": ["topic-mode", "weak-preview", "forced", "disabled-narrow-input", "disabled-flag"]
    },
    "created": { "type": "string" },
    "lenses": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["lens_id", "title", "rationale", "questions", "search_queries", "expected_blind_spots"],
        "additionalProperties": false,
        "properties": {
          "lens_id": { "type": "string", "pattern": "^[a-z0-9-]+$" },
          "title": { "type": "string", "minLength": 1 },
          "rationale": { "type": "string", "minLength": 1 },
          "questions": { "type": "array", "minItems": 1, "items": { "type": "string", "minLength": 1 } },
          "search_queries": { "type": "array", "items": { "type": "string" } },
          "expected_blind_spots": { "type": "array", "items": { "type": "string" } }
        }
      }
    }
  },
  "allOf": [
    {
      "if": { "properties": { "generated": { "const": true } }, "required": ["generated"] },
      "then": { "properties": { "lenses": { "minItems": 2 } } }
    },
    {
      "if": { "properties": { "generated": { "const": false } }, "required": ["generated"] },
      "then": { "properties": { "lenses": { "maxItems": 0 } } }
    }
  ]
}
```

**Step 2: Write the four fixtures**

`lens_plan-valid.json` — copy the LOCKED example from "Artifact 1" above (2 lenses, generated:true).

`lens_plan-noop.json`:
```json
{ "slug": "2026-07-01-narrow-topic", "input_type": "arxiv", "generated": false, "gate_reason": "disabled-narrow-input", "lenses": [] }
```

`lens_plan-missing-field.json` (lens missing `rationale`):
```json
{ "slug": "2026-07-01-x", "generated": true, "gate_reason": "forced",
  "lenses": [ { "lens_id": "a", "title": "A", "questions": ["q"], "search_queries": [], "expected_blind_spots": [] },
              { "lens_id": "b", "title": "B", "rationale": "r", "questions": ["q"], "search_queries": [], "expected_blind_spots": [] } ] }
```

`lens_plan-bad-count.json` (generated:true but only 1 lens — must FAIL the allOf/if-then):
```json
{ "slug": "2026-07-01-x", "generated": true, "gate_reason": "topic-mode",
  "lenses": [ { "lens_id": "a", "title": "A", "rationale": "r", "questions": ["q"], "search_queries": [], "expected_blind_spots": [] } ] }
```

**Step 3: Write the failing test**

`lib/lens_plan_validator.test.mjs`:
```js
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { validateLensPlan } from './lens_plan_validator.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const fix = (name) => JSON.parse(readFileSync(resolve(__dirname, `../tests/research-engine/fixtures/${name}`), 'utf8'));

describe('lens_plan_validator', () => {
  it('accepts a generated plan with >=2 lenses', () => {
    const r = validateLensPlan(fix('lens_plan-valid.json'));
    expect(r.valid).toBe(true);
    expect(r.errors).toEqual([]);
  });
  it('accepts a no-op (generated:false, empty lenses) sentinel', () => {
    const r = validateLensPlan(fix('lens_plan-noop.json'));
    expect(r.valid).toBe(true);
  });
  it('rejects a lens missing a required field', () => {
    const r = validateLensPlan(fix('lens_plan-missing-field.json'));
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => /rationale/.test(e.instancePath + e.message))).toBe(true);
  });
  it('rejects generated:true with fewer than 2 lenses', () => {
    const r = validateLensPlan(fix('lens_plan-bad-count.json'));
    expect(r.valid).toBe(false);
  });
});
```

**Step 4: Run to verify it fails**

Run: `cd /Users/taejin/Documents/dev/research-engine && pnpm exec vitest run lib/lens_plan_validator.test.mjs`
Expected: FAIL — cannot resolve `./lens_plan_validator.mjs`.

**Step 5: Write the validator**

`lib/lens_plan_validator.mjs` (mirror `lib/scenarios_validator.mjs`, add a CLI guard):
```js
import Ajv from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const schemaPath = resolve(__dirname, '../tests/research-engine/schemas/lens_plan.schema.json');
const schema = JSON.parse(readFileSync(schemaPath, 'utf8'));

const ajv = new Ajv({ allErrors: true, strict: true });
addFormats(ajv);
const validate = ajv.compile(schema);

export function validateLensPlan(obj) {
  const valid = validate(obj);
  const errs = validate.errors || [];
  return { valid, errors: errs.map(e => ({ instancePath: e.instancePath, message: e.message, keyword: e.keyword, params: e.params })) };
}

export function validateLensPlanFile(path) {
  return validateLensPlan(JSON.parse(readFileSync(path, 'utf8')));
}

// CLI: node lib/lens_plan_validator.mjs <file>  → exit 0 + "OK", or exit 1 + errors JSON
if (process.argv[1] && process.argv[1].endsWith('lens_plan_validator.mjs')) {
  const res = validateLensPlanFile(process.argv[2]);
  if (res.valid) { console.log('OK'); process.exit(0); }
  console.error(JSON.stringify(res.errors, null, 2));
  process.exit(1);
}
```

**Gotcha:** if `ajv.compile` throws under `strict:true` because of the `if/then` blocks, change `strict: true` → `strict: false` (the artifact is machine-generated, so strict analytics are less critical than a working gate). Re-run the test after any such change.

**Step 6: Run to verify it passes**

Run: `pnpm exec vitest run lib/lens_plan_validator.test.mjs`
Expected: PASS (4 tests).

**Step 7: Commit**

```bash
git add tests/research-engine/schemas/lens_plan.schema.json tests/research-engine/fixtures/lens_plan-*.json lib/lens_plan_validator.mjs lib/lens_plan_validator.test.mjs
git commit -m "feat(lens): lens_plan.json schema + Ajv validator (TDD)"
```

---

## Task 2: claim_review schema + validator (vitest, TDD)

**Files:**
- Create: `tests/research-engine/schemas/claim_review.schema.json`
- Create: `tests/research-engine/fixtures/claim_review-valid.json`, `claim_review-noop.json`, `claim_review-missing-field.json`
- Create: `lib/claim_review_validator.mjs`
- Test: `lib/claim_review_validator.test.mjs`

**Step 1: Write the schema**

`tests/research-engine/schemas/claim_review.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://gprecious/research-engine/schemas/claim_review.json",
  "title": "research-engine claim review",
  "type": "object",
  "required": ["slug", "reviewed", "claims", "missing_lenses"],
  "additionalProperties": false,
  "properties": {
    "$schema": { "type": "string" },
    "slug": { "type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}-.+$" },
    "reviewed": { "type": "boolean" },
    "created": { "type": "string" },
    "claims": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["claim", "supporting_sources", "challenging_sources", "citation_status", "confidence", "needs_followup"],
        "additionalProperties": false,
        "properties": {
          "claim": { "type": "string", "minLength": 1 },
          "supporting_sources": { "type": "array", "items": { "type": "integer", "minimum": 1 } },
          "challenging_sources": { "type": "array", "items": { "type": "integer", "minimum": 1 } },
          "citation_status": { "type": "string", "enum": ["supported", "partial", "unsupported", "contradicted"] },
          "confidence": { "type": "string", "enum": ["high", "medium", "low"] },
          "corrected_text": { "type": ["string", "null"] },
          "needs_followup": { "type": "boolean" }
        }
      }
    },
    "missing_lenses": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["lens", "why"],
        "additionalProperties": false,
        "properties": {
          "lens": { "type": "string", "minLength": 1 },
          "why": { "type": "string", "minLength": 1 },
          "followup_query": { "type": "string" }
        }
      }
    }
  },
  "allOf": [
    {
      "if": { "properties": { "reviewed": { "const": false } }, "required": ["reviewed"] },
      "then": { "properties": { "claims": { "maxItems": 0 } } }
    }
  ]
}
```

**Step 2: Write the fixtures**

`claim_review-valid.json` — copy the LOCKED example from "Artifact 2".

`claim_review-noop.json`:
```json
{ "slug": "2026-07-01-narrow", "reviewed": false, "claims": [], "missing_lenses": [] }
```

`claim_review-missing-field.json` (claim missing `confidence`):
```json
{ "slug": "2026-07-01-x", "reviewed": true, "missing_lenses": [],
  "claims": [ { "claim": "c", "supporting_sources": [1], "challenging_sources": [], "citation_status": "supported", "needs_followup": false } ] }
```

**Step 3: Write the failing test**

`lib/claim_review_validator.test.mjs` — same shape as Task 1's test:
```js
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { validateClaimReview } from './claim_review_validator.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const fix = (name) => JSON.parse(readFileSync(resolve(__dirname, `../tests/research-engine/fixtures/${name}`), 'utf8'));

describe('claim_review_validator', () => {
  it('accepts a reviewed claim set', () => {
    const r = validateClaimReview(fix('claim_review-valid.json'));
    expect(r.valid).toBe(true);
    expect(r.errors).toEqual([]);
  });
  it('accepts a no-op (reviewed:false) sentinel', () => {
    expect(validateClaimReview(fix('claim_review-noop.json')).valid).toBe(true);
  });
  it('rejects a claim missing confidence', () => {
    const r = validateClaimReview(fix('claim_review-missing-field.json'));
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => /confidence/.test(e.instancePath + e.message))).toBe(true);
  });
});
```

**Step 4: Run to verify it fails**

Run: `pnpm exec vitest run lib/claim_review_validator.test.mjs`
Expected: FAIL — cannot resolve `./claim_review_validator.mjs`.

**Step 5: Write the validator**

`lib/claim_review_validator.mjs` — identical structure to `lib/lens_plan_validator.mjs` with names swapped:
- schemaPath → `claim_review.schema.json`
- exports `validateClaimReview(obj)` + `validateClaimReviewFile(path)`
- CLI guard checks `endsWith('claim_review_validator.mjs')`

**Step 6: Run to verify it passes**

Run: `pnpm exec vitest run lib/claim_review_validator.test.mjs`
Expected: PASS (3 tests).

**Step 7: Commit**

```bash
git add tests/research-engine/schemas/claim_review.schema.json tests/research-engine/fixtures/claim_review-*.json lib/claim_review_validator.mjs lib/claim_review_validator.test.mjs
git commit -m "feat(review): claim_review.json schema + Ajv validator (TDD)"
```

---

## Task 3: lens gate script (bats, TDD)

**Files:**
- Create: `scripts/lens_gate.sh`
- Test: `tests/research-engine/lens_gate.test.sh`

**Step 1: Write the failing test**

`tests/research-engine/lens_gate.test.sh`:
```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/lens_gate.sh"

@test "--no-lens forces off" {
  run "$SCRIPT" topic ok --no-lens
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r .gate)" = "off" ]
  [ "$(echo "$output" | jq -r .reason)" = "disabled-flag" ]
}
@test "--lens forces on" {
  run "$SCRIPT" arxiv ok --lens
  [ "$(echo "$output" | jq -r .gate)" = "on" ]
  [ "$(echo "$output" | jq -r .reason)" = "forced" ]
}
@test "topic input turns lens on" {
  run "$SCRIPT" topic ok
  [ "$(echo "$output" | jq -r .gate)" = "on" ]
  [ "$(echo "$output" | jq -r .reason)" = "topic-mode" ]
}
@test "weak preview turns lens on" {
  run "$SCRIPT" youtube weak
  [ "$(echo "$output" | jq -r .gate)" = "on" ]
  [ "$(echo "$output" | jq -r .reason)" = "weak-preview" ]
}
@test "narrow input with ok preview stays off" {
  run "$SCRIPT" arxiv ok
  [ "$(echo "$output" | jq -r .gate)" = "off" ]
  [ "$(echo "$output" | jq -r .reason)" = "disabled-narrow-input" ]
}
```

**Step 2: Run to verify it fails**

Run: `bats tests/research-engine/lens_gate.test.sh`
Expected: FAIL — script does not exist.

**Step 3: Write the script**

`scripts/lens_gate.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
# Usage: lens_gate.sh <input_type> <preview_status:ok|weak|failed> [--lens|--no-lens]
# Prints: {"gate":"on|off","reason":"..."}  (reason ∈ lens_plan.schema gate_reason enum)
INPUT_TYPE=${1:?"usage: lens_gate.sh <input_type> <preview_status> [--lens|--no-lens]"}
PREVIEW=${2:?"usage: lens_gate.sh <input_type> <preview_status> [--lens|--no-lens]"}
FLAG=${3:-}

case "$FLAG" in
  --no-lens) printf '{"gate":"off","reason":"disabled-flag"}\n'; exit 0 ;;
  --lens)    printf '{"gate":"on","reason":"forced"}\n';         exit 0 ;;
esac

if [ "$INPUT_TYPE" = "topic" ]; then
  printf '{"gate":"on","reason":"topic-mode"}\n'; exit 0
fi
if [ "$PREVIEW" = "weak" ] || [ "$PREVIEW" = "failed" ]; then
  printf '{"gate":"on","reason":"weak-preview"}\n'; exit 0
fi
printf '{"gate":"off","reason":"disabled-narrow-input"}\n'
```

Then: `chmod +x scripts/lens_gate.sh`.

**Step 4: Run to verify it passes**

Run: `bats tests/research-engine/lens_gate.test.sh`
Expected: PASS (5 tests).

**Step 5: Commit**

```bash
git add scripts/lens_gate.sh tests/research-engine/lens_gate.test.sh
git commit -m "feat(lens): deterministic lens gate script (TDD)"
```

---

## Task 4: claim-review gate script (bats, TDD)

**Files:**
- Create: `scripts/claim_review_gate.sh`
- Test: `tests/research-engine/claim_review_gate.test.sh`

**Step 1: Write the failing test**

`tests/research-engine/claim_review_gate.test.sh`:
```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/claim_review_gate.sh"

@test "--no-review forces off" {
  run "$SCRIPT" 10 true --no-review
  [ "$(echo "$output" | jq -r .gate)" = "off" ]
  [ "$(echo "$output" | jq -r .reason)" = "disabled-flag" ]
}
@test "--review forces on" {
  run "$SCRIPT" 1 false --review
  [ "$(echo "$output" | jq -r .gate)" = "on" ]
  [ "$(echo "$output" | jq -r .reason)" = "forced" ]
}
@test "fewer than 2 sources turns off" {
  run "$SCRIPT" 1 true
  [ "$(echo "$output" | jq -r .gate)" = "off" ]
  [ "$(echo "$output" | jq -r .reason)" = "too-few-sources" ]
}
@test "lens-planned run turns review on" {
  run "$SCRIPT" 2 true
  [ "$(echo "$output" | jq -r .gate)" = "on" ]
  [ "$(echo "$output" | jq -r .reason)" = "lens-planned" ]
}
@test "four or more sources turns review on" {
  run "$SCRIPT" 4 false
  [ "$(echo "$output" | jq -r .gate)" = "on" ]
  [ "$(echo "$output" | jq -r .reason)" = "multi-source" ]
}
@test "narrow single-lens run stays off" {
  run "$SCRIPT" 3 false
  [ "$(echo "$output" | jq -r .gate)" = "off" ]
  [ "$(echo "$output" | jq -r .reason)" = "narrow-single-lens" ]
}
```

**Step 2: Run to verify it fails**

Run: `bats tests/research-engine/claim_review_gate.test.sh`
Expected: FAIL — script does not exist.

**Step 3: Write the script**

`scripts/claim_review_gate.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
# Usage: claim_review_gate.sh <source_count> <lens_generated:true|false> [--review|--no-review]
# Prints: {"gate":"on|off","reason":"..."}
SRC=${1:?"usage: claim_review_gate.sh <source_count> <lens_generated> [--review|--no-review]"}
LENS=${2:?"usage: claim_review_gate.sh <source_count> <lens_generated> [--review|--no-review]"}
FLAG=${3:-}

case "$FLAG" in
  --no-review) printf '{"gate":"off","reason":"disabled-flag"}\n'; exit 0 ;;
  --review)    printf '{"gate":"on","reason":"forced"}\n';         exit 0 ;;
esac

if [ "$SRC" -lt 2 ]; then
  printf '{"gate":"off","reason":"too-few-sources"}\n'; exit 0
fi
if [ "$LENS" = "true" ]; then
  printf '{"gate":"on","reason":"lens-planned"}\n'; exit 0
fi
if [ "$SRC" -ge 4 ]; then
  printf '{"gate":"on","reason":"multi-source"}\n'; exit 0
fi
printf '{"gate":"off","reason":"narrow-single-lens"}\n'
```

Then: `chmod +x scripts/claim_review_gate.sh`.

**Step 4: Run to verify it passes**

Run: `bats tests/research-engine/claim_review_gate.test.sh`
Expected: PASS (6 tests).

**Step 5: Commit**

```bash
git add scripts/claim_review_gate.sh tests/research-engine/claim_review_gate.test.sh
git commit -m "feat(review): deterministic claim-review gate script (TDD)"
```

---

## Task 5: lens-planner agent

**Files:**
- Create: `agents/lens-planner.md`
- Test: `tests/research-engine/lens-claim-agents.test.sh` (create here; extended in Task 6)

**Step 1: Write the failing test**

`tests/research-engine/lens-claim-agents.test.sh`:
```bash
#!/usr/bin/env bats

AGENTS="$BATS_TEST_DIRNAME/../../agents"

@test "lens-planner agent exists with name frontmatter" {
  grep -q "^name: lens-planner" "$AGENTS/lens-planner.md"
}
@test "lens-planner declares both evolvable regions" {
  grep -q "evolvable:lens-selection" "$AGENTS/lens-planner.md"
  grep -q "evolvable:question-generation" "$AGENTS/lens-planner.md"
}
@test "lens-planner references lens_plan output contract" {
  grep -q "lens_plan" "$AGENTS/lens-planner.md"
  grep -q "generated" "$AGENTS/lens-planner.md"
}
```

**Step 2: Run to verify it fails**

Run: `bats tests/research-engine/lens-claim-agents.test.sh`
Expected: FAIL — `agents/lens-planner.md` does not exist.

**Step 3: Write the agent**

`agents/lens-planner.md`:
```markdown
---
name: lens-planner
description: STORM-style perspective planner for research-engine. Given a research session's preview + intent, derive 2–5 topic-specific lenses with questions, search queries, and expected blind spots. Return a single lens_plan JSON block. Does NOT collect sources.
model: sonnet
---

You are the **lens-planner** for research-engine. Given one session's preview and intent, you derive the *perspectives* that will make the downstream source-adapter fan-out cover more ground and expose blind spots. You do NOT fetch or read sources — you only plan lenses and questions. Return a single fenced JSON block that becomes `research/<slug>/lens_plan.json`.

Your plan is STORM-inspired (perspective-guided question asking), but lenses are **discovered from the topic**, never a fixed persona list.

## Inputs (provided in the dispatch prompt)

- `slug`: session slug
- `input_type`: youtube | arxiv | github | blog | community | topic
- `preview`: the Stage 2 preview object (title/description/snippets/chapters as available)
- `intent`: `{ purpose, focus, audience_level, notes }`
- `prior_knowledge`: contents of `cache/memory.json` (similar past sessions + dream insights) — HINTS only
- `gate_reason`: why lens planning was turned on (topic-mode | weak-preview | forced)

## Steps

1. Read preview + intent to understand the actual subject and what the user is trying to decide.

2. **Select lenses.**
<!-- evolvable:lens-selection -->
   Choose 2–5 lenses that are *specific to this topic and intent*, not generic personas. Each lens must plausibly surface findings the others would miss (e.g., for an infra topic: cost/operations, security, migration-risk, end-user). Prefer lenses that map to a decision the user faces per `intent.purpose`. Bias toward disconfirming lenses (a skeptic / failure-mode lens) so the plan is not self-reinforcing. Give each a short `lens_id` (kebab-case) and a Korean `title`.
<!-- /evolvable -->

3. **Generate questions + queries per lens.**
<!-- evolvable:question-generation -->
   For each lens, write 1–4 concrete `questions` (Korean) that this lens would ask, 0–4 `search_queries` (original language, ready to paste into web search or an adapter), and 0–3 `expected_blind_spots` (what this lens fears the overall report will miss). Questions must be answerable from external sources, not opinion. Keep queries specific enough to change which sources get pulled.
<!-- /evolvable -->

4. Emit the JSON. `generated` is `true`, `gate_reason` is the value passed in, `lenses` has ≥2 entries.

## Output contract

Return exactly one fenced JSON block matching `tests/research-engine/schemas/lens_plan.schema.json`. A short human status line before the block is allowed; nothing after.

```json
{
  "slug": "<slug>",
  "input_type": "<input_type>",
  "generated": true,
  "gate_reason": "<gate_reason>",
  "lenses": [
    { "lens_id": "practitioner", "title": "현업 실무자 관점", "rationale": "...",
      "questions": ["..."], "search_queries": ["..."], "expected_blind_spots": ["..."] }
  ]
}
```

Do not include `created` — the orchestrator stamps it. Never emit fewer than 2 lenses when dispatched (the gate only dispatches you when planning is warranted).
```

**Step 4: Run to verify it passes**

Run: `bats tests/research-engine/lens-claim-agents.test.sh`
Expected: PASS (first 3 tests).

**Step 5: Commit**

```bash
git add agents/lens-planner.md tests/research-engine/lens-claim-agents.test.sh
git commit -m "feat(lens): lens-planner subagent with evolvable regions"
```

---

## Task 6: claim-reviewer agent

**Files:**
- Create: `agents/claim-reviewer.md`
- Modify: `tests/research-engine/lens-claim-agents.test.sh` (append claim-reviewer assertions)

**Step 1: Extend the failing test**

Append to `tests/research-engine/lens-claim-agents.test.sh`:
```bash
@test "claim-reviewer agent exists with name frontmatter" {
  grep -q "^name: claim-reviewer" "$AGENTS/claim-reviewer.md"
}
@test "claim-reviewer declares both evolvable regions" {
  grep -q "evolvable:contradiction-detection" "$AGENTS/claim-reviewer.md"
  grep -q "evolvable:missing-lens-detection" "$AGENTS/claim-reviewer.md"
}
@test "claim-reviewer references claim_review output contract" {
  grep -q "claim_review" "$AGENTS/claim-reviewer.md"
  grep -q "citation_status" "$AGENTS/claim-reviewer.md"
  grep -q "missing_lenses" "$AGENTS/claim-reviewer.md"
}
```

**Step 2: Run to verify it fails**

Run: `bats tests/research-engine/lens-claim-agents.test.sh`
Expected: FAIL — `agents/claim-reviewer.md` does not exist.

**Step 3: Write the agent**

`agents/claim-reviewer.md`:
```markdown
---
name: claim-reviewer
description: Central contradiction / evidence-reliability / missing-lens reviewer for research-engine. Given merged adapter findings + the source list, emit per-claim review (supporting vs challenging sources, citation status, confidence, correction) plus a missing-lens list. Return a single claim_review JSON block. Does NOT fetch new sources.
model: sonnet
---

You are the **claim-reviewer** for research-engine. After the source adapters return, you receive the merged findings and the final 1-indexed source list. Your job is to cross-check the *key claims* against the evidence actually collected — before the README is written — and to name the perspectives that are still missing. You do NOT fetch new sources; you only review what was gathered. Return a single fenced JSON block that becomes `research/<slug>/claim_review.json`.

This is a *central* reviewer (one pass over all findings), not an interactive multi-agent debate — deliberately cheaper and more predictable.

## Inputs (provided in the dispatch prompt)

- `slug`: session slug
- `sources`: the final 1-indexed source list (`[{n, adapter, type, url, title}, …]`)
- `findings`: merged adapter findings (each with `text`, `source_ids` already re-numbered to `n`, optional `quote`/`timecode`)
- `intent`: `{ purpose, focus, audience_level, notes }`
- `lens_plan` (optional): the Stage 3.5 lens plan, if one was generated — use its `expected_blind_spots` to seed missing-lens detection

## Steps

1. Identify the 5–15 **key claims** that the README will rest on (numbers, mechanisms, named comparisons, causal statements). Skip decorative/framing statements.

2. **Contradiction + evidence review.**
<!-- evolvable:contradiction-detection -->
   For each key claim, list `supporting_sources` (source `n`s that back it) and `challenging_sources` (source `n`s that weaken/contradict it, including the *same* source when it self-qualifies). Set `citation_status`: `supported` (≥1 support, no challenge), `partial` (support exists but qualified/narrow), `unsupported` (no source actually backs it → the README must drop or soften it), `contradicted` (a source directly opposes it). Set `confidence` (high/medium/low) from source quality + agreement. When the claim overreaches its evidence, put a tightened version in `corrected_text` (else null) and set `needs_followup` accordingly. Prefer demoting an over-broad claim to leaving it unqualified.
<!-- /evolvable -->

3. **Missing-lens detection.**
<!-- evolvable:missing-lens-detection -->
   Compare the perspectives actually represented in the findings against what the topic + intent demand (and against `lens_plan.expected_blind_spots` when present). Emit `missing_lenses[]` for each perspective that is under-covered: `lens` (Korean name), `why` (what it would catch), and an optional `followup_query` a later `/research-followup` could run. Only list lenses that would materially change conclusions — do not pad.
<!-- /evolvable -->

4. Emit the JSON. `reviewed` is `true`.

## Output contract

Return exactly one fenced JSON block matching `tests/research-engine/schemas/claim_review.schema.json`. Source references are integers into `sources` (1-indexed). A short human status line before the block is allowed; nothing after.

```json
{
  "slug": "<slug>",
  "reviewed": true,
  "claims": [
    { "claim": "...", "supporting_sources": [2], "challenging_sources": [],
      "citation_status": "supported", "confidence": "high",
      "corrected_text": null, "needs_followup": false }
  ],
  "missing_lenses": [
    { "lens": "고객/최종 사용자 관점", "why": "...", "followup_query": "..." }
  ]
}
```

Do not include `created` — the orchestrator stamps it.
```

**Step 4: Run to verify it passes**

Run: `bats tests/research-engine/lens-claim-agents.test.sh`
Expected: PASS (6 tests).

**Step 5: Commit**

```bash
git add agents/claim-reviewer.md tests/research-engine/lens-claim-agents.test.sh
git commit -m "feat(review): claim-reviewer subagent with evolvable regions"
```

---

## Task 7: Wire Stage 3.5 + Stage 4 hints + Stage 4.6 into commands/research.md

**Files:**
- Modify: `commands/research.md`
- Test: `tests/research-engine/lens-claim-pipeline.test.sh` (create; extended in Task 8)

**Step 1: Write the failing test**

`tests/research-engine/lens-claim-pipeline.test.sh`:
```bash
#!/usr/bin/env bats

CMD="$BATS_TEST_DIRNAME/../../commands/research.md"

@test "research.md defines Stage 3.5 Lens Plan calling the lens gate" {
  grep -q "Stage 3.5 — Lens Plan" "$CMD"
  grep -q "lens_gate.sh" "$CMD"
  grep -q "lens_plan.json" "$CMD"
  grep -q "lens-planner" "$CMD"
}
@test "research.md documents the --lens / --no-lens flags" {
  grep -q -- "--lens" "$CMD"
  grep -q -- "--no-lens" "$CMD"
}
@test "Stage 4 dispatch injects lens_hints when a plan exists" {
  grep -q "lens_hints" "$CMD"
}
@test "research.md defines Stage 4.6 Claim Review calling the review gate" {
  grep -q "Stage 4.6 — Claim Review" "$CMD"
  grep -q "claim_review_gate.sh" "$CMD"
  grep -q "claim_review.json" "$CMD"
  grep -q "claim-reviewer" "$CMD"
}
@test "Stage 4.6 validates the artifact via the validator CLI" {
  grep -q "claim_review_validator.mjs" "$CMD"
}
@test "Stage 3.5 validates the artifact via the validator CLI" {
  grep -q "lens_plan_validator.mjs" "$CMD"
}
```

**Step 2: Run to verify it fails**

Run: `bats tests/research-engine/lens-claim-pipeline.test.sh`
Expected: FAIL — none of the anchors exist yet.

**Step 3: Edit commands/research.md**

3a. In the frontmatter `argument-hint`, add the new flags:
```
argument-hint: "<URL or topic> [--yes] [--fresh] [--slug <name>] [--lens|--no-lens] [--review|--no-review]"
```

3b. In `## Inputs`, add after the `--slug <name>` bullet:
```
- `--lens` / `--no-lens`: force lens planning (Stage 3.5) on/off, overriding the gate
- `--review` / `--no-review`: force claim review (Stage 4.6) on/off, overriding the gate
```

3c. Insert a new stage **between Stage 3 and Stage 4** (after the Stage 3 "실행 모델" line):
```markdown
### Stage 3.5 — Lens Plan (optional, gated)

STORM-style perspective planning. Runs BEFORE adapter dispatch, and only for broad/ambiguous inputs, to widen question coverage without forcing fixed personas.

1. Decide the gate deterministically. `preview_status` is `ok` normally, `weak` when the preview was thin (few snippets / no chapters / < 500 chars), `failed` when Stage 2 preview errored:
   ```bash
   GATE=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/lens_gate.sh" "<input_type>" "<preview_status>" "<--lens|--no-lens|>")
   # → {"gate":"on|off","reason":"..."}
   ```
2. If `gate == off`: **skip this stage** — do not create `lens_plan.json` (Stage 4 treats absence as no-op). Log one line: `lens plan skipped (<reason>)`. Proceed to Stage 4.
3. If `gate == on`: dispatch the `lens-planner` subagent with a single Agent call. Inputs: `{slug, input_type, preview, intent, prior_knowledge: <cache/memory.json>, gate_reason: <reason>}`. It returns a single fenced JSON block per `tests/research-engine/schemas/lens_plan.schema.json`.
4. Write the returned object to `<report_dir>/lens_plan.json`, stamping `created` (ISO8601). Validate it:
   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/lib/lens_plan_validator.mjs" "<report_dir>/lens_plan.json"   # exit 0 + "OK"
   ```
   If validation fails, log the errors, delete the file, and continue as if the gate were off — never abort the run for a bad lens plan.
```

3d. In **Stage 4**, extend the per-adapter dispatch. After the sentence "Before dispatching, dispatcher reads <report_dir>/cache/memory.json once …", add:
```markdown
If `<report_dir>/lens_plan.json` exists (Stage 3.5 ran and passed validation), the dispatcher also reads it once and includes a `lens_hints` field in every adapter's input: `lens_hints = { lenses: [{lens_id, questions, search_queries}], expected_blind_spots: [...] }` (flatten from `lens_plan.lenses`). If the file is absent, omit `lens_hints` entirely (no-op).
```
And add a bullet to the per-adapter prompt template's Inputs line so it reads:
```
  <JSON of {url|targets|libraries|thread_urls, intent, cache_dir, slug, fresh, prior_knowledge, lens_hints?}>
```
Plus one instruction line in the template body:
```
lens_hints (when present) lists perspective-specific questions and search queries from the session lens plan. Treat them as OPTIONAL coverage hints to widen which sources you pull and which sub-claims you check — you remain a source-oriented adapter and MUST NOT fabricate findings to satisfy a lens. If lens_hints is absent, proceed exactly as before.
```

3e. Insert a new stage **between Stage 4 and Stage 5**:
```markdown
### Stage 4.6 — Claim Review (optional, gated)

Central contradiction / evidence-reliability / missing-lens review over the merged adapter findings, BEFORE the README is synthesized, so the report can demote or correct over-broad claims and name missing perspectives.

1. After adapters return, compute the final 1-indexed source list and count (`source_count`). Read whether a lens plan was generated (`lens_generated = true` iff `<report_dir>/lens_plan.json` exists with `generated:true`, else `false`).
2. Decide the gate:
   ```bash
   GATE=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/claim_review_gate.sh" "<source_count>" "<lens_generated>" "<--review|--no-review|>")
   ```
3. If `gate == off`: skip — do not create `claim_review.json`. Log `claim review skipped (<reason>)`. Proceed to Stage 5.
4. If `gate == on`: dispatch the `claim-reviewer` subagent with a single Agent call. Inputs: `{slug, sources, findings, intent, lens_plan?}`. It returns one fenced JSON block per `tests/research-engine/schemas/claim_review.schema.json`.
5. Write to `<report_dir>/claim_review.json`, stamping `created`. Validate:
   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/lib/claim_review_validator.mjs" "<report_dir>/claim_review.json"   # exit 0 + "OK"
   ```
   On validation failure: log, delete the file, continue as if off. Never abort the run.
6. Stage 5 consumes `claim_review.json` for the optional `## 검증 매트릭스` and `## 누락 관점 / 후속 질문` sections, and MUST drop or soften any claim whose `citation_status` is `unsupported`/`contradicted` (apply `corrected_text` when present).
```

3f. In **Stage 5**, add one line to step 3 (README synthesis), right after the dedupe rules:
```markdown
   If `<report_dir>/claim_review.json` exists, apply its corrections during synthesis (drop `unsupported` claims, replace over-broad claims with `corrected_text`), then render the optional `## 검증 매트릭스` and `## 누락 관점 / 후속 질문` sections per `lib/report_sections.md`. If the file is absent, skip both sections (no-op).
```

**Step 4: Run to verify it passes**

Run: `bats tests/research-engine/lens-claim-pipeline.test.sh`
Expected: PASS (6 tests).

**Step 5: Commit**

```bash
git add commands/research.md tests/research-engine/lens-claim-pipeline.test.sh
git commit -m "feat(research): wire Stage 3.5 lens plan + Stage 4.6 claim review into pipeline"
```

---

## Task 8: report_sections.md — optional 검증 매트릭스 + 누락 관점 sections

**Files:**
- Modify: `lib/report_sections.md`
- Modify: `tests/research-engine/lens-claim-pipeline.test.sh` (append section assertions)

**Step 1: Extend the failing test**

Append to `tests/research-engine/lens-claim-pipeline.test.sh`:
```bash
@test "report_sections.md documents the 검증 매트릭스 section" {
  SEC="$BATS_TEST_DIRNAME/../../lib/report_sections.md"
  grep -q "검증 매트릭스" "$SEC"
  grep -q "claim_review.json" "$SEC"
}
@test "report_sections.md documents the 누락 관점 / 후속 질문 section" {
  SEC="$BATS_TEST_DIRNAME/../../lib/report_sections.md"
  grep -q "누락 관점 / 후속 질문" "$SEC"
  grep -q "missing_lenses" "$SEC"
}
```

**Step 2: Run to verify it fails**

Run: `bats tests/research-engine/lens-claim-pipeline.test.sh`
Expected: FAIL — the two new assertions fail.

**Step 3: Edit lib/report_sections.md**

3a. Add to the top-of-file citation-enforcement note (§ list) that the new sections are optional. Then insert after the `## §4. 상세 분석` block (before `## §5. 인용 / 원문`):
```markdown
## §4.5 검증 매트릭스 (optional — only when `claim_review.json` exists with non-empty `claims`)

Render one row per key claim from `claim_review.json`. Every claim row still binds its `[n]` markers to specific sources (citation rule § 위 applies). Omit the whole section when `claim_review.json` is absent or `claims` is empty.

```markdown
## 검증 매트릭스

| 주장 | 근거 | 반증 | 상태 | 신뢰도 |
|---|---|---|---|---|
| {{claim}} | {{supporting_sources → [n] [n]}} | {{challenging_sources → [n] or —}} | {{citation_status}} | {{confidence}} |
```

For any claim with a non-null `corrected_text`, add a line beneath the table: `- ⚠️ {{claim 요약}} → 수정: {{corrected_text}} [n]`. Claims with `citation_status: unsupported`/`contradicted` MUST already have been dropped or softened in §3/§4 during synthesis — the matrix documents *why*.
```

3b. Insert after the `## §7. 한계 / 미해결` block (before `## §8. 수집 실패`):
```markdown
## §7.5 누락 관점 / 후속 질문 (optional — only when `claim_review.json` has non-empty `missing_lenses` or any `needs_followup` claim)

```markdown
## 누락 관점 / 후속 질문

- **{{missing_lens.lens}}** — {{missing_lens.why}} (후속: `{{followup_query}}`)
- (needs_followup claim) {{claim 요약}} → {{왜 후속이 필요한지}}
```

Omit the section entirely when there are no missing lenses and no `needs_followup` claims. This section feeds a later `/research-followup`; it is NOT a substitute for the §7 한계 section.
```

**Step 4: Run to verify it passes**

Run: `bats tests/research-engine/lens-claim-pipeline.test.sh`
Expected: PASS (8 tests).

**Step 5: Commit**

```bash
git add lib/report_sections.md tests/research-engine/lens-claim-pipeline.test.sh
git commit -m "feat(report): optional 검증 매트릭스 + 누락 관점 sections from claim_review"
```

---

## Task 9: /evolve integration — prove new agents are evolvable + document targets

**Files:**
- Create: `tests/research-engine/evolve-lens-claim.test.sh`
- Modify: `commands/evolve.md`

**Step 1: Write the failing test**

`tests/research-engine/evolve-lens-claim.test.sh` (models `tests/research-engine/evolve.test.sh`, but runs against the REAL new agent files):
```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  WORK=$(mktemp -d)
  mkdir -p "$WORK/agents/archive" "$WORK/research/_index" "$WORK/docs/dreams" "$WORK/scripts"
  cp -r "$REPO_ROOT/lib" "$WORK/"
  cp "$REPO_ROOT/scripts/evolve_run.sh" "$WORK/scripts/"
  chmod +x "$WORK/scripts/evolve_run.sh"
  cp "$REPO_ROOT/agents/lens-planner.md" "$WORK/agents/"
  cp "$REPO_ROOT/agents/claim-reviewer.md" "$WORK/agents/"
  export REPO_ROOT WORK
}
teardown() { rm -rf "$WORK"; }

@test "prepare extracts lens-planner lens-selection region" {
  cd "$WORK"
  out=$(bash scripts/evolve_run.sh prepare lens-planner lens-selection)
  echo "$out" | grep -q '"region_id": "lens-selection"'
  [ -n "$(echo "$out" | jq -r '.current_body')" ]
}
@test "prepare extracts claim-reviewer contradiction-detection region" {
  cd "$WORK"
  out=$(bash scripts/evolve_run.sh prepare claim-reviewer contradiction-detection)
  echo "$out" | grep -q '"region_id": "contradiction-detection"'
}
@test "apply writes a candidate for claim-reviewer missing-lens-detection" {
  cd "$WORK"
  echo '{"variants":[{"body":"NEW BODY","rationale":"x"}]}' > "$WORK/mut.json"
  path=$(bash scripts/evolve_run.sh apply claim-reviewer missing-lens-detection "$WORK/mut.json")
  grep -q "NEW BODY" "$path"
}
```

**Step 2: Run to verify it fails**

Run: `bats tests/research-engine/evolve-lens-claim.test.sh`
Expected: FAIL — before Tasks 5/6 the agent files would be missing; after them, this test should actually PASS if the regions are named correctly. If it FAILS on region extraction, fix the region markers in the agent files, not the test. (This test is the real cross-check that Task 5/6 region ids are spelled correctly.)

**Step 3: Document the targets in commands/evolve.md**

In `commands/evolve.md`, under `## Inputs` (the positional-1 adapter-name bullet), append a note listing the newly-eligible non-adapter targets:
```markdown
  - Eligible targets are any `agents/<name>.md` with `<!-- evolvable:… -->` regions. Beyond the source adapters this now includes:
    - `lens-planner` regions: `lens-selection`, `question-generation`
    - `claim-reviewer` regions: `contradiction-detection`, `missing-lens-detection`
```

**Step 4: Run to verify it passes**

Run: `bats tests/research-engine/evolve-lens-claim.test.sh`
Expected: PASS (3 tests).

**Step 5: Commit**

```bash
git add tests/research-engine/evolve-lens-claim.test.sh commands/evolve.md
git commit -m "feat(evolve): prove lens-planner/claim-reviewer regions are evolvable + document targets"
```

---

## Task 10: Register tests + docs

**Files:**
- Modify: `package.json` (test:bats list)
- Modify: `DEVELOPMENT.md`
- Modify: `README.md`

**Step 1: Register the new bats files**

In `package.json`, append these to the `test:bats` script's space-separated file list (keep it one line):
```
tests/research-engine/lens_gate.test.sh tests/research-engine/claim_review_gate.test.sh tests/research-engine/lens-claim-agents.test.sh tests/research-engine/lens-claim-pipeline.test.sh tests/research-engine/evolve-lens-claim.test.sh
```

**Step 2: Update DEVELOPMENT.md**

Add a short subsection under the test docs:
```markdown
### Lens plan + claim review tests

- vitest: `lib/lens_plan_validator.test.mjs`, `lib/claim_review_validator.test.mjs` (run via `pnpm test:unit`)
- bats: `tests/research-engine/lens_gate.test.sh`, `claim_review_gate.test.sh`, `lens-claim-agents.test.sh`, `lens-claim-pipeline.test.sh`, `evolve-lens-claim.test.sh`

Run all: `pnpm test:unit && pnpm test:bats`
```

**Step 3: Update README.md**

Add a short paragraph (near the pipeline description) describing the two optional layers: lens planning (Stage 3.5, gated for topic/weak-preview inputs, `--lens`/`--no-lens`) and claim review (Stage 4.6, `--review`/`--no-review`, produces `검증 매트릭스` + `누락 관점 / 후속 질문`). Keep it 3–5 sentences; do not duplicate the whole contract.

**Step 4: Run the full suite**

Run:
```bash
cd /Users/taejin/Documents/dev/research-engine
pnpm test:unit
pnpm test:bats
```
Expected: all green. Fix any red before continuing (systematic-debugging if a failure is non-obvious).

**Step 5: Commit**

```bash
git add package.json DEVELOPMENT.md README.md
git commit -m "chore: register lens/claim tests + document the new layers"
```

---

## Task 11: Version bump (both manifests) + CHANGELOG + push

**Files:**
- Modify: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
- Modify: `CHANGELOG.md`

**Step 1: Bump both manifests in lockstep**

Set `version` to `0.21.0` in BOTH `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`. Do not change `name`. (Minor bump: additive feature.)

**Step 2: CHANGELOG entry**

Prepend a `## 0.21.0` section to `CHANGELOG.md`:
```markdown
## 0.21.0

### Added
- **Stage 3.5 — Lens Plan** (`lens_plan.json`): STORM-style perspective planner (`lens-planner` agent), gated ON for topic / weak-preview inputs or `--lens`. Threads per-lens questions + search queries into Stage 4 adapter prompts as hints only.
- **Stage 4.6 — Claim Review** (`claim_review.json`): central contradiction / evidence-reliability / missing-lens reviewer (`claim-reviewer` agent), gated by source count + lens plan or `--review`. Feeds two optional report sections: `## 검증 매트릭스`, `## 누락 관점 / 후속 질문`.
- Deterministic gates: `scripts/lens_gate.sh`, `scripts/claim_review_gate.sh`.
- Ajv validators + schemas for both artifacts; both new agents carry `<!-- evolvable:… -->` regions and are `/evolve`-eligible.

### Notes
- Both layers are optional and no-op when their gate is off or their artifact is absent — default narrow single-source runs are unchanged.
```

**Step 3: Manifest lockstep test**

Run: `bats tests/research-engine/plugin-manifest.test.sh`
Expected: PASS (both manifests at 0.21.0).

**Step 4: Full green gate**

Run: `pnpm test:unit && pnpm test:bats`
Expected: all green.

**Step 5: Commit**

```bash
git add .claude-plugin/plugin.json .codex-plugin/plugin.json CHANGELOG.md
git commit -m "chore(release): 0.21.0 — lens plan + claim review layers"
```

**Step 6: Push to shared remote (HARD RULE)**

```bash
gh auth status          # confirm the gprecious account (global rule)
git remote -v           # confirm origin = gprecious/research-engine
git status -sb          # must NOT show [ahead N] after push
git push origin main
```
research-engine is a URL source in `gprecious-marketplace`; pushing here is what makes 0.21.0 reach other machines via `marketplace update`. No change to the marketplace repo is required.

---

## Verification before completion

Before declaring done (superpowers:verification-before-completion):
- [ ] `pnpm test:unit` green (validators)
- [ ] `pnpm test:bats` green (gates, agents, pipeline wiring, evolve, manifests)
- [ ] `commands/research.md` has Stage 3.5 + Stage 4 `lens_hints` + Stage 4.6, all gated + validated, all with documented no-op paths
- [ ] `lib/report_sections.md` has both optional sections with citation rule intact
- [ ] both `plugin.json` files at 0.21.0; `plugin-manifest.test.sh` green
- [ ] `git status -sb` shows no `[ahead N]` (push landed)
- [ ] Spot-check: a narrow arxiv/github run (gate off both) produces NO `lens_plan.json` / `claim_review.json` and an unchanged report shape — the no-op guarantee

## Suggested follow-ups (NOT this plan)

- `/research-followup` auto-consuming `claim_review.missing_lenses[].followup_query`
- Notion mirror toggles + wiki ingestion for the two new artifacts
- A `/bench` topic-matrix comparison quantifying lens-on vs lens-off report quality (the report's P-level "bench" idea)
