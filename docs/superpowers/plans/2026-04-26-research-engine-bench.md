# research-engine vs Claude Code Mini-Bench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `/bench` slash command that runs a 5-topic × 2-mode × N=2 matrix comparing `research-engine` against a vanilla Claude Code (general-purpose subagent) baseline, scores both via LLM-as-judge on a 5-axis rubric, and emits an `improvement opportunities` report driving the next research-engine PR cycle.

**Architecture:** Thin slash command orchestrator → shell harness (`bench/run.sh`) that spawns isolated `claude -p` subprocesses → quantitative metrics (`bench/collect_metrics.sh`) → LLM-as-judge (`bench/judge.py`) → templated markdown report (`bench/report.py`). Serial execution, idempotent runs, partial-failure-tolerant. All artifacts under `bench/runs/<date>/`.

**Tech Stack:** Bash (with `set -euo pipefail`), Python 3 stdlib only (no new deps), `jq` + `yq` for YAML/JSON, Bats for shell-script unit tests, `claude -p` for both runs and judge calls.

**Spec:** `docs/superpowers/specs/2026-04-26-research-engine-bench-design.md`

---

## File Structure

### Create

| Path | Responsibility |
|---|---|
| `bench/topics.yaml` | 5 production topics + 1 smoke topic, with `baseline_prompt` per topic |
| `bench/schemas/meta.schema.json` | JSON Schema for per-run `meta.json` |
| `bench/schemas/judge.schema.json` | JSON Schema for per-topic `judge.json` |
| `bench/schemas/results.schema.json` | JSON Schema for top-level `results.json` |
| `bench/run.sh` | Orchestrator — preflight, run matrix, dispatch judge + report |
| `bench/collect_metrics.sh` | Reads `output.md`/`stderr.log` → writes `meta.json` |
| `bench/judge.py` | LLM-as-judge — Stage 4a (cross-mode) + Stage 4b (reproducibility) + `--self-check` + `--dry-run` |
| `bench/report.py` | Reads `results.json` → renders `report.md` from template |
| `bench/lib/judge_prompt.md` | System prompt for the judge — strict-JSON output + 5 axes |
| `commands/bench.md` | `/bench` slash command — thin entry, invokes `run.sh` |
| `tests/bats/test_collect_metrics.bats` | Unit test for `collect_metrics.sh` against fixture |
| `tests/bats/test_judge.bats` | Unit test for `judge.py` self-check + dry-run |
| `tests/bats/test_report.bats` | Unit test for `report.py` against fixture `results.json` |
| `tests/bats/test_bench_run.bats` | Unit test for `run.sh --check` (preflight only) |
| `tests/fixtures/bench-output/output.md` | Sample research output for metrics test |
| `tests/fixtures/bench-output/stderr.log` | Sample stderr |
| `tests/fixtures/bench-results/results.json` | Sample aggregated results for report test |
| `tests/fixtures/bench-judge/canned_response.json` | Canned judge JSON for dry-run testing |
| `tests/acceptance/bench.md` | Manual acceptance checklist |

### Modify

| Path | Change |
|---|---|
| `README.md` | Add `/bench` usage section |
| `CHANGELOG.md` | New entry |
| `DEVELOPMENT.md` | Note new bats files |
| `.gitignore` | Add `bench/runs/` (raw outputs are reproducible — not committed; only design/code committed) |

### Do not touch

`commands/research.md`, `commands/research-followup.md`, `commands/research-visualize.md`, `agents/*`, `scripts/*`, `lib/*` (except adding judge prompt under `bench/lib/`). The bench is a self-contained subsystem and **must not** modify `/research` itself — that would taint the comparison.

---

## Order of Tasks

Bottom-up + spike-first:

1. Spike: verify `claude -p` plugin isolation (resolves spec §9.1)
2. Spike: verify token-usage exposure via `claude -p` (resolves spec §9.2)
3. JSON schemas (meta, judge, results)
4. `topics.yaml` skeleton + smoke topic + 5 placeholder production topics
5. `tests/fixtures/bench-output/` sample fixture
6. `bench/collect_metrics.sh` + bats test (TDD)
7. `bench/lib/judge_prompt.md`
8. `bench/judge.py` core + `--dry-run` + bats test (TDD)
9. `bench/judge.py --self-check` + bats test
10. `tests/fixtures/bench-results/results.json` fixture
11. `bench/report.py` + bats test (TDD)
12. `bench/run.sh --check` (preflight) + bats test (TDD)
13. `bench/run.sh` main loop (uses spike findings from Tasks 1–2)
14. `commands/bench.md` slash command
15. End-to-end smoke (`/bench --topic smoke --no-judge`)
16. Pick real topic URLs, fill `topics.yaml`
17. Run full matrix, generate report, surface improvements
18. Docs + CHANGELOG + commit

---

## Task 1: Spike — Verify `claude -p` Plugin Isolation

**Goal:** Resolve spec open question §9.1 — does `claude -p` support `--no-plugins` (or equivalent), and does the env var `RESEARCH_ENGINE_DISABLE=1` actually disable the plugin?

**Files:**
- Create: `bench/SPIKE-NOTES.md` (delete after Task 13 — these are throwaway notes, not part of the shipped harness)

- [ ] **Step 1: Discover claude CLI flag surface**

Run: `claude -p --help 2>&1 | head -100`

Expected: list of flags. Search output for `plugin`, `disable`, `no-plugin`. Capture the actual flag name (or note absence).

- [ ] **Step 2: Test plugin disable via flag (if exists)**

If a flag like `--no-plugins` was found, run:

```bash
claude -p --no-plugins "List all slash commands available to you. Output only as a markdown list."
```

Expected: research-engine slash commands (`/research`, `/research-followup`, `/research-visualize`, `/bench`) should NOT appear.

- [ ] **Step 3: Test plugin disable via env var**

```bash
RESEARCH_ENGINE_DISABLE=1 claude -p "List all slash commands available to you."
```

Expected: same outcome — research-engine slash commands missing. If the env var is not honored (likely — research-engine doesn't currently read it), this falls back to flag-only.

- [ ] **Step 4: Document findings to bench/SPIKE-NOTES.md**

Write findings:

```markdown
# Spike notes — to be deleted after Task 13

## Plugin isolation finding (resolves spec §9.1)
- `--no-plugins` flag: <YES with name `XXXX` | NO>
- `RESEARCH_ENGINE_DISABLE=1` env: <honored | not honored>
- **Decision for run.sh**: <chosen approach + fallback>

## Token exposure finding (resolves spec §9.2)
- (filled in Task 2)
```

- [ ] **Step 5: Commit notes**

```bash
git add bench/SPIKE-NOTES.md
git commit -m "chore(bench): record claude-p plugin-isolation spike findings"
```

---

## Task 2: Spike — Verify Token Usage Exposure

**Goal:** Resolve spec §9.2 — does `claude -p` expose model token counts in non-interactive mode?

- [ ] **Step 1: Run a small `claude -p` call with verbose output**

```bash
claude -p --verbose "What is 2+2?" 2>&1 | tee /tmp/claude-verbose.log
```

(Substitute `--verbose` with whatever flag, if any, was discovered in Task 1 step 1.)

- [ ] **Step 2: Search log for token counts**

```bash
grep -iE 'token|input.*[0-9]+|output.*[0-9]+|usage' /tmp/claude-verbose.log
```

Expected: either token usage lines appear (capture format) or nothing matches.

- [ ] **Step 3: Append findings to SPIKE-NOTES.md**

Replace the placeholder section:

```markdown
## Token exposure finding (resolves spec §9.2)
- claude -p exposes tokens: <YES via flag/format X | NO>
- **Decision for collect_metrics.sh**: <parse format / record null>
```

- [ ] **Step 4: Commit**

```bash
git add bench/SPIKE-NOTES.md
git commit -m "chore(bench): record claude-p token-exposure spike findings"
```

---

## Task 3: JSON Schemas

**Files:**
- Create: `bench/schemas/meta.schema.json`
- Create: `bench/schemas/judge.schema.json`
- Create: `bench/schemas/results.schema.json`

- [ ] **Step 1: Write meta.schema.json**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Per-run metadata",
  "type": "object",
  "required": ["status"],
  "properties": {
    "status": { "enum": ["ok", "failed", "timeout", "skipped"] },
    "wall_time_sec": { "type": "integer", "minimum": 0 },
    "word_count": { "type": "integer", "minimum": 0 },
    "citation_count": { "type": "integer", "minimum": 0 },
    "external_link_count": { "type": "integer", "minimum": 0 },
    "model_tokens": {
      "type": ["object", "null"],
      "properties": {
        "input": { "type": "integer", "minimum": 0 },
        "output": { "type": "integer", "minimum": 0 }
      }
    },
    "exit_code": { "type": "integer" }
  },
  "additionalProperties": false
}
```

- [ ] **Step 2: Write judge.schema.json**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Per-topic judge output",
  "type": "object",
  "required": ["topic_id", "judge_model", "cross_mode", "reproducibility"],
  "properties": {
    "topic_id": { "type": "string" },
    "judge_model": { "type": "string" },
    "judged_at": { "type": "string", "format": "date-time" },
    "blind_label_map": {
      "type": "object",
      "properties": {
        "A": { "enum": ["re", "baseline"] },
        "B": { "enum": ["re", "baseline"] }
      },
      "required": ["A", "B"]
    },
    "judge_blind": { "type": "boolean" },
    "cross_mode": {
      "type": "object",
      "properties": {
        "re":       { "$ref": "#/definitions/axis_scores" },
        "baseline": { "$ref": "#/definitions/axis_scores" }
      },
      "required": ["re", "baseline"]
    },
    "reproducibility": {
      "type": "object",
      "properties": {
        "re":       { "type": ["number", "null"], "minimum": 0, "maximum": 10 },
        "baseline": { "type": ["number", "null"], "minimum": 0, "maximum": 10 }
      },
      "required": ["re", "baseline"]
    }
  },
  "definitions": {
    "axis_scores": {
      "type": "object",
      "properties": {
        "coverage":  { "type": ["number", "null"], "minimum": 0, "maximum": 10 },
        "citation":  { "type": ["number", "null"], "minimum": 0, "maximum": 10 },
        "depth":     { "type": ["number", "null"], "minimum": 0, "maximum": 10 },
        "structure": { "type": ["number", "null"], "minimum": 0, "maximum": 10 },
        "rationale": { "type": "string" }
      },
      "required": ["coverage", "citation", "depth", "structure"]
    }
  }
}
```

- [ ] **Step 3: Write results.schema.json**

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Aggregated bench results",
  "type": "object",
  "required": ["bench_date", "judge_model", "topics", "aggregate"],
  "properties": {
    "bench_date": { "type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$" },
    "judge_model": { "type": "string" },
    "model_under_test": { "type": "string" },
    "topics": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "category", "re", "baseline"],
        "properties": {
          "id":       { "type": "string" },
          "category": { "enum": ["youtube", "arxiv", "github", "blog", "topic"] },
          "re":       { "$ref": "#/definitions/mode_block" },
          "baseline": { "$ref": "#/definitions/mode_block" },
          "delta":    { "type": ["number", "null"] },
          "judge_rationale": { "type": "string" }
        }
      }
    },
    "aggregate": {
      "type": "object",
      "properties": {
        "re_avg":       { "type": ["number", "null"] },
        "baseline_avg": { "type": ["number", "null"] },
        "delta_avg":    { "type": ["number", "null"] },
        "by_axis":      { "type": "object" },
        "by_category":  { "type": "object" }
      }
    }
  },
  "definitions": {
    "mode_block": {
      "type": "object",
      "properties": {
        "run1": { "type": "object" },
        "run2": { "type": "object" },
        "scores": { "type": "object" },
        "weighted_total": { "type": ["number", "null"] }
      }
    }
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add bench/schemas/
git commit -m "feat(bench): JSON schemas for meta, judge, results"
```

---

## Task 4: `topics.yaml` Skeleton (Smoke Only)

**Files:**
- Create: `bench/topics.yaml`

The initial commit ships only the smoke topic. The 5 production topics are added in Task 16 once the harness is proven, so we never commit placeholder URLs.

- [ ] **Step 1: Write topics.yaml**

```yaml
# Mini-bench topic set. See docs/superpowers/specs/2026-04-26-research-engine-bench-design.md
#
# Fairness rule (production topics, added in Task 16): every `baseline_prompt`
# shares ONLY the keywords "deep research" + "구조화된 markdown" + "인용 포함"
# (or near-equivalents). Any extra guidance leaks research-engine prompt
# design into the baseline.
#
# Available substitutions inside baseline_prompt:
#   {url}    → the topic's url field (skipped if null)
#   {topic}  → the id stripped of category prefix (e.g., topic-foo → foo)

topics:
  # Smoke topic — used by `bench/run.sh --topic smoke --no-judge` for plumbing
  # validation. Stable, short, well-known target so smoke is reproducible.
  - id: smoke
    category: arxiv
    url: https://arxiv.org/abs/1706.03762
    baseline_prompt: |
      이 논문에 대한 deep research 리포트를 만들어줘: {url}
```

- [ ] **Step 2: Commit**

```bash
git add bench/topics.yaml
git commit -m "feat(bench): topics.yaml with smoke topic (production topics in Task 16)"
```

---

## Task 5: Output Fixture for Metrics Tests

**Files:**
- Create: `tests/fixtures/bench-output/output.md`
- Create: `tests/fixtures/bench-output/stderr.log`

- [ ] **Step 1: Write a representative output.md fixture**

```markdown
# Sample research output

## TL;DR

Mamba is a state-space model architecture that achieves linear-time sequence
modeling [1] [2]. Key benchmarks show it outperforming Transformers on selected
long-context tasks [3].

## 상세 분석

Approach: selective state-space mechanism with input-dependent transitions.
See the original paper [1] for derivations and [Mamba GitHub](https://github.com/state-spaces/mamba)
for implementation details. The [HuggingFace blog post](https://huggingface.co/blog/mamba)
provides accessible context.

## Sources

[1] https://arxiv.org/abs/2312.00752
[2] https://blog.example.com/mamba-explainer
[3] https://github.com/state-spaces/mamba

External links count target: 5 (3 numbered citations + 2 inline links).
Citation count target: 5 ([1], [2], [3] appear 5 times collectively across body).
Word count target: ~70.
```

- [ ] **Step 2: Write a sample stderr.log**

```
[claude-p] Loaded plugin: research-engine v0.4.0
[claude-p] Tokens used: input=12340, output=2100
[claude-p] Done in 612s
```

(Adapt token-line format based on Task 2 spike findings.)

- [ ] **Step 3: Commit**

```bash
git add tests/fixtures/bench-output/
git commit -m "test(bench): sample output + stderr fixtures for metrics tests"
```

---

## Task 6: `collect_metrics.sh` (TDD)

**Files:**
- Create: `tests/bats/test_collect_metrics.bats`
- Create: `bench/collect_metrics.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../bench/collect_metrics.sh"
FIXTURE="$BATS_TEST_DIRNAME/../fixtures/bench-output"

setup() {
  TMPDIR_T="$(mktemp -d)"
  cp "$FIXTURE/output.md" "$TMPDIR_T/output.md"
  cp "$FIXTURE/stderr.log" "$TMPDIR_T/stderr.log"
}
teardown() { rm -rf "$TMPDIR_T"; }

@test "writes meta.json with status ok on successful run" {
  run "$SCRIPT" "$TMPDIR_T" 1700000000 1700000612
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_T/meta.json" ]
  status_field=$(jq -r '.status' "$TMPDIR_T/meta.json")
  [ "$status_field" = "ok" ]
}

@test "computes wall_time_sec from start/end args" {
  "$SCRIPT" "$TMPDIR_T" 1700000000 1700000612
  wt=$(jq -r '.wall_time_sec' "$TMPDIR_T/meta.json")
  [ "$wt" = "612" ]
}

@test "counts numbered citations in output.md" {
  "$SCRIPT" "$TMPDIR_T" 1700000000 1700000612
  cc=$(jq -r '.citation_count' "$TMPDIR_T/meta.json")
  [ "$cc" -ge 3 ]
}

@test "counts external links in output.md" {
  "$SCRIPT" "$TMPDIR_T" 1700000000 1700000612
  ec=$(jq -r '.external_link_count' "$TMPDIR_T/meta.json")
  [ "$ec" -ge 3 ]
}

@test "marks status failed when output.md is missing" {
  rm "$TMPDIR_T/output.md"
  "$SCRIPT" "$TMPDIR_T" 1700000000 1700000612
  status_field=$(jq -r '.status' "$TMPDIR_T/meta.json")
  [ "$status_field" = "failed" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/bats/test_collect_metrics.bats`
Expected: all 5 tests fail with "No such file or directory: bench/collect_metrics.sh".

- [ ] **Step 3: Implement collect_metrics.sh**

```bash
#!/usr/bin/env bash
# collect_metrics.sh — extract per-run quantitative metrics
# Usage: collect_metrics.sh <run_dir> <start_unix> <end_unix>
# Writes <run_dir>/meta.json. Always exits 0.
set -euo pipefail

RUN_DIR="${1:?run_dir required}"
START="${2:?start required}"
END="${3:?end required}"

OUTPUT="$RUN_DIR/output.md"
STDERR="$RUN_DIR/stderr.log"
META="$RUN_DIR/meta.json"

WALL=$(( END - START ))

if [[ ! -s "$OUTPUT" ]]; then
  jq -n --argjson wall "$WALL" '{status:"failed", wall_time_sec:$wall, word_count:0, citation_count:0, external_link_count:0, model_tokens:null, exit_code:null}' > "$META"
  exit 0
fi

WORDS=$(wc -w < "$OUTPUT" | tr -d ' ')

# Numbered citations [1], [2], etc — count occurrences (not unique).
CITATIONS=$(grep -oE '\[[0-9]+\]' "$OUTPUT" | wc -l | tr -d ' ')

# External links: any URL appearing as bare http(s):// or in markdown link form.
LINKS=$(grep -oE 'https?://[^ )"]+' "$OUTPUT" | sort -u | wc -l | tr -d ' ')

# Token usage — best-effort parse from stderr. Format depends on Task 2 spike.
# Adjust the regex below to whatever claude -p actually emits.
TOKENS_JSON="null"
if [[ -f "$STDERR" ]]; then
  if INPUT=$(grep -oE 'input=[0-9]+' "$STDERR" | head -1 | cut -d= -f2) && \
     OUTPUT_T=$(grep -oE 'output=[0-9]+' "$STDERR" | head -1 | cut -d= -f2) && \
     [[ -n "$INPUT" && -n "$OUTPUT_T" ]]; then
    TOKENS_JSON=$(jq -n --argjson i "$INPUT" --argjson o "$OUTPUT_T" '{input:$i, output:$o}')
  fi
fi

jq -n \
  --argjson wall "$WALL" \
  --argjson words "$WORDS" \
  --argjson cit "$CITATIONS" \
  --argjson links "$LINKS" \
  --argjson tokens "$TOKENS_JSON" \
  '{status:"ok", wall_time_sec:$wall, word_count:$words, citation_count:$cit, external_link_count:$links, model_tokens:$tokens, exit_code:0}' \
  > "$META"
```

- [ ] **Step 4: Make executable, run tests**

```bash
chmod +x bench/collect_metrics.sh
bats tests/bats/test_collect_metrics.bats
```

Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add bench/collect_metrics.sh tests/bats/test_collect_metrics.bats
git commit -m "feat(bench): collect_metrics.sh with bats coverage"
```

---

## Task 7: Judge Prompt File

**Files:**
- Create: `bench/lib/judge_prompt.md`

- [ ] **Step 1: Write the system prompt**

```markdown
# Judge system prompt

You are an impartial judge comparing two research reports written for the same
input. You will see them as **report A** and **report B**. You do NOT know which
research engine produced which report and MUST NOT speculate.

## Output format

You MUST output exactly one JSON object, no markdown fences, no preamble:

```json
{
  "A": {
    "coverage":  <0-10>,
    "citation":  <0-10>,
    "depth":     <0-10>,
    "structure": <0-10>,
    "rationale": "one short sentence per axis, joined with '; '"
  },
  "B": { ... same shape ... }
}
```

## Scoring axes (0–10 each)

1. **Coverage** — does the report touch the topic's core areas, or miss obvious ones?
2. **Citation Quality** — are citations specific, traceable, and tied to claims (not decorative)?
3. **Depth** — does it surface real insight beyond surface summary?
4. **Structure** — is there a usable TL;DR, hierarchy, navigable headings?

## Rules

- Score on quality only. Length is NOT depth — terse-but-insightful beats verbose-but-shallow.
- A report that fails to address the input topic at all gets near-zero across the board.
- If you cannot tell A and B apart, both get the same score.
- Never reference the labels "research-engine", "plugin", "subagent", or any meta-context. If you do, the judgment is invalid.

## Reproducibility prompt (separate call)

When invoked with two reports for the SAME mode (run1 vs run2), output:

```json
{
  "reproducibility": <0-10>,
  "rationale": "one short sentence"
}
```

Score 10 = same core facts, same source set, same structure. Score 0 = unrelated
content. Surface differences in fact set or claim direction; ignore wording.
```

- [ ] **Step 2: Commit**

```bash
git add bench/lib/judge_prompt.md
git commit -m "feat(bench): judge system prompt — strict-JSON 5-axis rubric"
```

---

## Task 8: `judge.py` Core (TDD)

**Files:**
- Create: `tests/fixtures/bench-judge/canned_response.json`
- Create: `tests/bats/test_judge.bats`
- Create: `bench/judge.py`

- [ ] **Step 1: Write canned-response fixture**

```json
{
  "A": {
    "coverage": 8.5,
    "citation": 9.0,
    "depth":    7.5,
    "structure": 9.0,
    "rationale": "Coverage broad; citations specific; depth solid; structure clean."
  },
  "B": {
    "coverage": 6.0,
    "citation": 5.5,
    "depth":    5.0,
    "structure": 7.0,
    "rationale": "Coverage partial; citations decorative; depth shallow; structure ok."
  }
}
```

- [ ] **Step 2: Write the failing test**

```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../bench/judge.py"
CANNED="$BATS_TEST_DIRNAME/../fixtures/bench-judge/canned_response.json"

setup() {
  TMPDIR_T="$(mktemp -d)"
  mkdir -p "$TMPDIR_T/topic-1/re/run1" "$TMPDIR_T/topic-1/baseline/run1"
  echo "# RE output" > "$TMPDIR_T/topic-1/re/run1/output.md"
  echo "# Baseline output" > "$TMPDIR_T/topic-1/baseline/run1/output.md"
}
teardown() { rm -rf "$TMPDIR_T"; }

@test "--dry-run prints prompt without invoking claude" {
  run "$SCRIPT" --dry-run --topic-dir "$TMPDIR_T/topic-1" --topic-id topic-1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "report A"
  echo "$output" | grep -q "report B"
}

@test "--from-fixture reads canned response and writes judge.json" {
  run "$SCRIPT" --from-fixture "$CANNED" --topic-dir "$TMPDIR_T/topic-1" --topic-id topic-1
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_T/topic-1/judge.json" ]
  topic=$(jq -r '.topic_id' "$TMPDIR_T/topic-1/judge.json")
  [ "$topic" = "topic-1" ]
}

@test "judge.json decodes blind labels (re/baseline both present)" {
  "$SCRIPT" --from-fixture "$CANNED" --topic-dir "$TMPDIR_T/topic-1" --topic-id topic-1
  re_cov=$(jq -r '.cross_mode.re.coverage' "$TMPDIR_T/topic-1/judge.json")
  base_cov=$(jq -r '.cross_mode.baseline.coverage' "$TMPDIR_T/topic-1/judge.json")
  [ "$re_cov" != "null" ]
  [ "$base_cov" != "null" ]
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bats tests/bats/test_judge.bats`
Expected: 3 tests fail with "judge.py not found".

- [ ] **Step 4: Implement bench/judge.py**

```python
#!/usr/bin/env python3
"""
judge.py — LLM-as-judge for bench runs.

Modes:
  --dry-run                                 # print built prompt, no claude call
  --from-fixture <file>                     # use canned JSON instead of claude
  --topic-dir <dir> --topic-id <id>         # judge a single topic
  --all --runs-dir bench/runs/<date>        # judge every topic under date
  --self-check --topic-dir <dir>            # feed RE as both A and B, expect equal scores
  --judge-model <model>                     # default claude-sonnet-4-6

Writes <topic-dir>/judge.json validated against bench/schemas/judge.schema.json.
Stdlib only (no pip deps).
"""
from __future__ import annotations
import argparse
import json
import os
import random
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROMPT_FILE = ROOT / "lib" / "judge_prompt.md"

DEFAULT_MODEL = "claude-sonnet-4-6"


def build_cross_mode_prompt(text_a: str, text_b: str, topic_id: str) -> str:
    system = PROMPT_FILE.read_text(encoding="utf-8")
    return (
        f"{system}\n\n"
        f"## Topic id (for your reference only)\n{topic_id}\n\n"
        f"## report A\n\n{text_a}\n\n## report B\n\n{text_b}\n"
    )


def build_repro_prompt(run1: str, run2: str, topic_id: str) -> str:
    system = PROMPT_FILE.read_text(encoding="utf-8")
    return (
        f"{system}\n\n"
        f"## Reproducibility judgment\n"
        f"Topic: {topic_id}\n\n"
        f"## report run1\n\n{run1}\n\n## report run2\n\n{run2}\n"
    )


def call_claude(prompt: str, model: str) -> str:
    """Invoke claude -p with the prompt; return stdout. Stdlib subprocess only."""
    proc = subprocess.run(
        ["claude", "-p", "--model", model, prompt],
        capture_output=True, text=True, timeout=600,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"claude -p exited {proc.returncode}: {proc.stderr[:500]}")
    return proc.stdout


def parse_strict_json(s: str) -> dict:
    """Parse first JSON object found in s. Raises on failure."""
    start = s.find("{")
    end = s.rfind("}")
    if start < 0 or end < 0 or end <= start:
        raise ValueError(f"no JSON object in response: {s[:200]}")
    return json.loads(s[start : end + 1])


def detect_blindness_break(s: str) -> bool:
    """Return True if response contains label-leak keywords."""
    bad = ("research-engine", "plugin", "subagent", "vanilla")
    return any(b in s.lower() for b in bad)


def judge_topic(
    topic_dir: Path,
    topic_id: str,
    *,
    dry_run: bool = False,
    fixture: Path | None = None,
    judge_model: str = DEFAULT_MODEL,
    self_check: bool = False,
) -> dict:
    re1 = (topic_dir / "re" / "run1" / "output.md").read_text(encoding="utf-8")
    base1 = (topic_dir / "baseline" / "run1" / "output.md").read_text(encoding="utf-8")

    # In self_check, both A and B are the SAME RE output — expect ~equal scores.
    if self_check:
        cand_a, cand_b = ("re", re1), ("re", re1)
    else:
        labelled = [("re", re1), ("baseline", base1)]
        random.shuffle(labelled)
        cand_a, cand_b = labelled[0], labelled[1]

    prompt = build_cross_mode_prompt(cand_a[1], cand_b[1], topic_id)

    if dry_run:
        print(prompt)
        return {}

    if fixture:
        raw = fixture.read_text(encoding="utf-8")
    else:
        raw = call_claude(prompt, judge_model)

    parsed = parse_strict_json(raw)
    blind = not detect_blindness_break(raw)

    decoded = {cand_a[0]: parsed["A"], cand_b[0]: parsed["B"]}
    # Self-check: both are "re" — collapse the dict so reads still work.
    if self_check:
        decoded = {"re": parsed["A"], "_self_check_b": parsed["B"]}

    # Reproducibility — only when run2 exists for both modes.
    repro = {"re": None, "baseline": None}
    for mode in ("re", "baseline"):
        run2_path = topic_dir / mode / "run2" / "output.md"
        run1_path = topic_dir / mode / "run1" / "output.md"
        if run2_path.exists() and run1_path.exists() and not (dry_run or fixture or self_check):
            r1 = run1_path.read_text(encoding="utf-8")
            r2 = run2_path.read_text(encoding="utf-8")
            r_raw = call_claude(build_repro_prompt(r1, r2, topic_id), judge_model)
            r_parsed = parse_strict_json(r_raw)
            repro[mode] = float(r_parsed.get("reproducibility")) if r_parsed.get("reproducibility") is not None else None

    out = {
        "topic_id": topic_id,
        "judge_model": judge_model if not fixture else "fixture",
        "judged_at": datetime.now(timezone.utc).isoformat(),
        "blind_label_map": {"A": cand_a[0], "B": cand_b[0]},
        "judge_blind": blind,
        "cross_mode": decoded if not self_check else {"re": parsed["A"], "baseline": parsed["B"]},
        "reproducibility": repro,
    }

    out_path = topic_dir / "judge.json"
    out_path.write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
    return out


def main() -> int:
    p = argparse.ArgumentParser(description="LLM-as-judge for bench runs.")
    p.add_argument("--topic-dir", type=Path)
    p.add_argument("--topic-id")
    p.add_argument("--all", action="store_true")
    p.add_argument("--runs-dir", type=Path)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--from-fixture", type=Path)
    p.add_argument("--self-check", action="store_true")
    p.add_argument("--judge-model", default=DEFAULT_MODEL)
    args = p.parse_args()

    if args.all:
        if not args.runs_dir or not args.runs_dir.exists():
            print(f"--runs-dir {args.runs_dir} missing", file=sys.stderr)
            return 2
        for topic_dir in sorted(args.runs_dir.iterdir()):
            if topic_dir.is_dir() and (topic_dir / "re").exists():
                try:
                    judge_topic(topic_dir, topic_dir.name,
                                judge_model=args.judge_model)
                    print(f"OK {topic_dir.name}", file=sys.stderr)
                except Exception as e:
                    print(f"FAIL {topic_dir.name}: {e}", file=sys.stderr)
        return 0

    if not args.topic_dir or not args.topic_id:
        print("--topic-dir and --topic-id required (or use --all)", file=sys.stderr)
        return 2

    judge_topic(
        args.topic_dir,
        args.topic_id,
        dry_run=args.dry_run,
        fixture=args.from_fixture,
        judge_model=args.judge_model,
        self_check=args.self_check,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 5: Make executable, run tests**

```bash
chmod +x bench/judge.py
bats tests/bats/test_judge.bats
```

Expected: all 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add bench/judge.py bench/lib/judge_prompt.md tests/bats/test_judge.bats tests/fixtures/bench-judge/
git commit -m "feat(bench): judge.py with --dry-run + --from-fixture + bats coverage"
```

---

## Task 9: Judge Self-Check (TDD)

**Files:**
- Modify: `tests/bats/test_judge.bats` (append a test)

- [ ] **Step 1: Append failing self-check test**

Open `tests/bats/test_judge.bats` and append:

```bash
@test "--self-check writes judge.json with both A and B (RE-as-both)" {
  # Self-check feeds the same RE output as both A and B.
  # We use --from-fixture to skip the live claude call; this just verifies
  # the wiring (judge.json exists, blind_label_map is set).
  run "$SCRIPT" --self-check --from-fixture "$CANNED" \
      --topic-dir "$TMPDIR_T/topic-1" --topic-id topic-1
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_T/topic-1/judge.json" ]
}
```

- [ ] **Step 2: Run test, expect pass (judge.py already supports this)**

Run: `bats tests/bats/test_judge.bats`
Expected: 4 tests PASS (the 3 from Task 8 + the new one).

If it fails: confirm `judge_topic(... self_check=True)` writes judge.json — the `--from-fixture` path bypasses live claude.

- [ ] **Step 3: Commit**

```bash
git add tests/bats/test_judge.bats
git commit -m "test(bench): cover judge.py --self-check path"
```

---

## Task 10: Aggregated Results Fixture

**Files:**
- Create: `tests/fixtures/bench-results/results.json`

- [ ] **Step 1: Write a minimal results.json fixture**

```json
{
  "bench_date": "2026-04-26",
  "judge_model": "claude-sonnet-4-6",
  "model_under_test": "claude-opus-4-7",
  "topics": [
    {
      "id": "youtube-sample",
      "category": "youtube",
      "re": {
        "scores": {"coverage": 8.5, "citation": 9.0, "depth": 8.0, "structure": 9.0, "reproducibility": 8.5},
        "weighted_total": 86.0
      },
      "baseline": {
        "scores": {"coverage": 6.0, "citation": 5.5, "depth": 5.0, "structure": 7.0, "reproducibility": 6.0},
        "weighted_total": 59.0
      },
      "delta": 27.0,
      "judge_rationale": "RE coverage broader, citations specific."
    },
    {
      "id": "arxiv-sample",
      "category": "arxiv",
      "re": {
        "scores": {"coverage": 7.0, "citation": 6.5, "depth": 7.5, "structure": 8.0, "reproducibility": 9.0},
        "weighted_total": 76.0
      },
      "baseline": {
        "scores": {"coverage": 7.5, "citation": 7.0, "depth": 6.5, "structure": 7.5, "reproducibility": 8.0},
        "weighted_total": 72.0
      },
      "delta": 4.0,
      "judge_rationale": "Close call; baseline slightly stronger on coverage."
    }
  ],
  "aggregate": {
    "re_avg": 81.0,
    "baseline_avg": 65.5,
    "delta_avg": 15.5,
    "by_axis": {
      "coverage":       {"re": 7.75, "baseline": 6.75},
      "citation":       {"re": 7.75, "baseline": 6.25},
      "depth":          {"re": 7.75, "baseline": 5.75},
      "structure":      {"re": 8.50, "baseline": 7.25},
      "reproducibility":{"re": 8.75, "baseline": 7.00}
    },
    "by_category": {
      "youtube": {"re": 86.0, "baseline": 59.0, "delta": 27.0},
      "arxiv":   {"re": 76.0, "baseline": 72.0, "delta": 4.0}
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add tests/fixtures/bench-results/results.json
git commit -m "test(bench): sample results.json fixture for report tests"
```

---

## Task 11: `report.py` (TDD)

**Files:**
- Create: `tests/bats/test_report.bats`
- Create: `bench/report.py`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../bench/report.py"
FIXTURE="$BATS_TEST_DIRNAME/../fixtures/bench-results/results.json"

setup() { TMPDIR_T="$(mktemp -d)"; cp "$FIXTURE" "$TMPDIR_T/results.json"; }
teardown() { rm -rf "$TMPDIR_T"; }

@test "renders report.md from results.json" {
  run "$SCRIPT" --results "$TMPDIR_T/results.json" --out "$TMPDIR_T/report.md"
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_T/report.md" ]
}

@test "report contains aggregate delta and per-axis breakdown" {
  "$SCRIPT" --results "$TMPDIR_T/results.json" --out "$TMPDIR_T/report.md"
  grep -q "delta_avg" "$TMPDIR_T/report.md" || grep -q "Δ" "$TMPDIR_T/report.md" || grep -q "+15.5" "$TMPDIR_T/report.md"
}

@test "report contains improvement opportunities section" {
  "$SCRIPT" --results "$TMPDIR_T/results.json" --out "$TMPDIR_T/report.md"
  grep -q -i "improvement opportunities" "$TMPDIR_T/report.md"
}

@test "report flags arxiv-sample as candidate (RE delta small or negative on coverage)" {
  "$SCRIPT" --results "$TMPDIR_T/results.json" --out "$TMPDIR_T/report.md"
  grep -q "arxiv-sample" "$TMPDIR_T/report.md"
}

@test "report contains limitations section" {
  "$SCRIPT" --results "$TMPDIR_T/results.json" --out "$TMPDIR_T/report.md"
  grep -q -i "limitations" "$TMPDIR_T/report.md"
}
```

- [ ] **Step 2: Run test, verify failure**

Run: `bats tests/bats/test_report.bats`
Expected: all 5 tests fail with "report.py not found".

- [ ] **Step 3: Implement bench/report.py**

```python
#!/usr/bin/env python3
"""
report.py — render bench/runs/<date>/report.md from results.json.

Usage:
  report.py --results <path/to/results.json> --out <path/to/report.md>

Stdlib only.
"""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path

LIMITATIONS = """\
## Limitations

- LLM-as-judge with same model family (Claude): potential self-favoring bias.
- N=2 trials per (topic, mode): too small for statistical confidence intervals.
- 5 topics = 1 per category: weak generalization across diverse content within a category.
- `baseline_prompt` phrasing is sensitive — small wording changes can move scores.
"""


def render(results: dict) -> str:
    lines: list[str] = []
    agg = results.get("aggregate", {})
    lines.append(f"# research-engine vs Claude Code bench — {results.get('bench_date', '?')}\n")
    lines.append("## Executive summary\n")
    lines.append(
        f"- RE average: **{agg.get('re_avg')}**\n"
        f"- Baseline average: **{agg.get('baseline_avg')}**\n"
        f"- Δ (RE − baseline): **{agg.get('delta_avg')}**\n"
        f"- Judge model: `{results.get('judge_model', '?')}`\n"
        f"- Model under test: `{results.get('model_under_test', '?')}`\n"
    )

    # Mermaid bar chart of axis averages
    by_axis = agg.get("by_axis", {})
    if by_axis:
        lines.append("\n```mermaid\nxychart-beta\n  title \"Per-axis averages (0–10)\"\n  x-axis [coverage, citation, depth, structure, reproducibility]\n")
        re_vals = [by_axis.get(a, {}).get("re", 0) for a in ("coverage","citation","depth","structure","reproducibility")]
        base_vals = [by_axis.get(a, {}).get("baseline", 0) for a in ("coverage","citation","depth","structure","reproducibility")]
        lines.append(f"  y-axis 0 --> 10\n  bar {re_vals}\n  bar {base_vals}\n```\n")

    lines.append("\n## Per-topic detail\n")
    lines.append("| topic | category | RE | baseline | Δ |\n|---|---|---|---|---|")
    for t in results.get("topics", []):
        lines.append(f"| {t['id']} | {t.get('category','?')} | {t.get('re',{}).get('weighted_total','?')} | {t.get('baseline',{}).get('weighted_total','?')} | {t.get('delta','?')} |")
    lines.append("")

    lines.append("\n## Improvement opportunities\n")
    opportunities: list[str] = []
    # Heuristic: any topic where RE didn't clearly beat baseline (delta ≤ 5) → candidate
    for t in results.get("topics", []):
        delta = t.get("delta") or 0
        if delta <= 5:
            opportunities.append(f"- **{t['id']}** (Δ={delta}): {t.get('judge_rationale','')}")
    # Heuristic: any axis where RE ≤ 6 → weak spot
    for axis, d in by_axis.items():
        if (d.get("re") or 10) <= 6:
            opportunities.append(f"- Axis **{axis}** RE avg = {d.get('re')} → research-engine weak spot")
    if not opportunities:
        opportunities.append("- (No obvious weak spots in this run; consider widening topic set.)")
    lines.extend(opportunities)
    lines.append("")

    lines.append(LIMITATIONS)
    return "\n".join(lines)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--results", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    args = p.parse_args()

    data = json.loads(args.results.read_text(encoding="utf-8"))
    args.out.write_text(render(data), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run tests**

```bash
chmod +x bench/report.py
bats tests/bats/test_report.bats
```

Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add bench/report.py tests/bats/test_report.bats
git commit -m "feat(bench): report.py renders results.json to markdown + improvements section"
```

---

## Task 12: `run.sh --check` Preflight (TDD)

**Files:**
- Create: `tests/bats/test_bench_run.bats`
- Create: `bench/run.sh` (preflight subset only — full loop in Task 13)

- [ ] **Step 1: Write the failing test**

The test uses `BENCH_REPO_ROOT_OVERRIDE` to relocate where `run.sh` looks for `topics.yaml` — that override is implemented in Step 3.

```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../bench/run.sh"

@test "--check runs preflight without errors when env is sane" {
  run env NOTION_TOKEN= "$SCRIPT" --check
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "claude"
  echo "$output" | grep -q "yq"
  echo "$output" | grep -q "jq"
  echo "$output" | grep -q "topics.yaml"
}

@test "--check fails when NOTION_TOKEN is set" {
  run env NOTION_TOKEN=secret_xxx "$SCRIPT" --check
  [ "$status" -ne 0 ]
}

@test "--check fails when topics.yaml is missing" {
  TMP="$(mktemp -d)"
  run env NOTION_TOKEN= BENCH_REPO_ROOT_OVERRIDE="$TMP" "$SCRIPT" --check
  [ "$status" -ne 0 ]
  rm -rf "$TMP"
}
```

- [ ] **Step 2: Run test, verify failure**

Run: `bats tests/bats/test_bench_run.bats`
Expected: 3 tests fail with "No such file or directory: bench/run.sh".

- [ ] **Step 3: Implement run.sh preflight stub**

```bash
#!/usr/bin/env bash
# bench/run.sh — orchestrator. Phase 1: preflight only (Task 12).
# Full run matrix lands in Task 13.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${BENCH_REPO_ROOT_OVERRIDE:-$(cd "$ROOT/.." && pwd)}"
TOPICS="$REPO_ROOT/bench/topics.yaml"

usage() {
  cat <<EOF
bench/run.sh — research-engine vs baseline mini-bench runner

  --check                Run preflight checks only and exit
  --topic <id>           Restrict to one topic
  --mode re|baseline     Restrict to one mode
  --force                Overwrite existing run outputs
  --no-judge             Skip judge stage
  --judge-only           Skip runs, only run judge
  --report-only          Skip runs + judge, only render report
  --judge-model <m>      Default: claude-sonnet-4-6
EOF
}

preflight() {
  local errors=0
  for cmd in claude yq jq python3; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "✓ $cmd present"
    else
      echo "✗ $cmd MISSING" >&2
      errors=$((errors+1))
    fi
  done

  if [[ -n "${NOTION_TOKEN:-}" ]]; then
    echo "✗ NOTION_TOKEN is set — bench refuses to run with Notion credentials in env (would risk push)" >&2
    errors=$((errors+1))
  else
    echo "✓ NOTION_TOKEN unset"
  fi

  if [[ ! -f "$TOPICS" ]]; then
    echo "✗ topics.yaml missing at $TOPICS" >&2
    errors=$((errors+1))
  else
    echo "✓ topics.yaml present"
    if ! yq '.topics[].id' "$TOPICS" >/dev/null 2>&1; then
      echo "✗ topics.yaml does not parse" >&2
      errors=$((errors+1))
    fi
  fi

  if (( errors > 0 )); then
    echo "Preflight FAILED ($errors error(s))" >&2
    return 1
  fi
  echo "Preflight OK"
}

CHECK_ONLY=0
case "${1:-}" in
  ""|--help|-h) usage; exit 0 ;;
  --check) CHECK_ONLY=1 ;;
esac

if (( CHECK_ONLY )); then
  preflight
  exit $?
fi

# Full run matrix is implemented in Task 13.
echo "TODO: full run matrix lands in Task 13" >&2
exit 2
```

- [ ] **Step 4: Run tests, verify pass**

```bash
chmod +x bench/run.sh
bats tests/bats/test_bench_run.bats
```

Expected: all 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add bench/run.sh tests/bats/test_bench_run.bats
git commit -m "feat(bench): run.sh --check preflight (full matrix to follow)"
```

---

## Task 13: `run.sh` Full Run Matrix

**Files:**
- Modify: `bench/run.sh` (replace the "TODO" stub with full loop)
- Delete: `bench/SPIKE-NOTES.md` (decisions are now embedded in run.sh)

This task implements the matrix loop using the spike findings from Tasks 1–2. The exact env/flag for plugin isolation depends on the spike outcome; the snippet below uses `RESEARCH_ENGINE_DISABLE=1` as the default with a `claude -p --no-plugins` line commented in/out per spike.

- [ ] **Step 1: Read SPIKE-NOTES.md and decide isolation strategy**

```bash
cat bench/SPIKE-NOTES.md
```

If `--no-plugins` worked: use it. Else: rely on env-only and add a warning in run.sh that isolation is best-effort.

- [ ] **Step 2: Replace run.sh stub with full loop**

```bash
#!/usr/bin/env bash
# bench/run.sh — research-engine vs baseline mini-bench runner.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${BENCH_REPO_ROOT_OVERRIDE:-$(cd "$ROOT/.." && pwd)}"
TOPICS="$REPO_ROOT/bench/topics.yaml"
DATE="$(date -u +%Y-%m-%d)"
RUNS_DIR="$REPO_ROOT/bench/runs/$DATE"

JUDGE_MODEL="claude-sonnet-4-6"
ONLY_TOPIC=""
ONLY_MODE=""
FORCE=0
NO_JUDGE=0
JUDGE_ONLY=0
REPORT_ONLY=0
TIMEOUT_S=1800

usage() { sed -n '2,/^$/p' "$0"; }

# (preflight() unchanged from Task 12 — keep it here)
preflight() {
  local errors=0
  for cmd in claude yq jq python3; do
    command -v "$cmd" >/dev/null 2>&1 \
      && echo "✓ $cmd present" \
      || { echo "✗ $cmd MISSING" >&2; errors=$((errors+1)); }
  done
  [[ -z "${NOTION_TOKEN:-}" ]] \
    && echo "✓ NOTION_TOKEN unset" \
    || { echo "✗ NOTION_TOKEN set — refusing" >&2; errors=$((errors+1)); }
  [[ -f "$TOPICS" ]] \
    && echo "✓ topics.yaml present" \
    || { echo "✗ topics.yaml missing at $TOPICS" >&2; errors=$((errors+1)); }
  if [[ -f "$TOPICS" ]] && ! yq '.topics[].id' "$TOPICS" >/dev/null 2>&1; then
    echo "✗ topics.yaml does not parse" >&2; errors=$((errors+1))
  fi
  (( errors > 0 )) && { echo "Preflight FAILED" >&2; return 1; }
  echo "Preflight OK"
}

run_one() {
  local topic_id="$1" mode="$2" run_n="$3"
  local out_dir="$RUNS_DIR/$topic_id/$mode/run$run_n"
  mkdir -p "$out_dir"

  if [[ -s "$out_dir/output.md" && "$FORCE" -ne 1 ]]; then
    echo "  [skip exists] $topic_id/$mode/run$run_n"
    return 0
  fi

  local url prompt
  url=$(yq -r ".topics[] | select(.id==\"$topic_id\") | .url" "$TOPICS")
  if [[ "$mode" == "re" ]]; then
    if [[ "$url" == "null" || -z "$url" ]]; then
      # topic mode — pass topic name, not URL
      local topic_text
      topic_text=$(yq -r ".topics[] | select(.id==\"$topic_id\") | .id" "$TOPICS" | sed 's/^topic-//')
      prompt="/research \"$topic_text\" --fresh --yes"
    else
      prompt="/research $url --fresh --yes"
    fi
  else
    # baseline — substitute {url} or {topic} into baseline_prompt
    local raw
    raw=$(yq -r ".topics[] | select(.id==\"$topic_id\") | .baseline_prompt" "$TOPICS")
    if [[ "$url" == "null" || -z "$url" ]]; then
      local topic_text
      topic_text=$(yq -r ".topics[] | select(.id==\"$topic_id\") | .id" "$TOPICS" | sed 's/^topic-//')
      prompt="${raw//\{topic\}/$topic_text}"
    else
      prompt="${raw//\{url\}/$url}"
    fi
  fi

  echo "  [$topic_id/$mode/run$run_n] starting"
  local start; start=$(date +%s)

  # Plugin-isolation strategy chosen from SPIKE-NOTES.md.
  # If --no-plugins flag exists, baseline gets it. Else env-only.
  local extra_args=()
  if [[ "$mode" == "baseline" ]]; then
    # extra_args+=(--no-plugins)  # uncomment if spike confirmed support
    :
  fi

  local exit_code=0
  env NOTION_TOKEN= RESEARCH_ENGINE_DISABLE=$([[ "$mode" == "baseline" ]] && echo 1 || echo 0) \
    timeout "$TIMEOUT_S" \
    claude -p "${extra_args[@]}" "$prompt" \
    > "$out_dir/output.md" 2> "$out_dir/stderr.log" \
    || exit_code=$?

  local end; end=$(date +%s)

  if (( exit_code == 124 )); then
    jq -n --argjson w $((end-start)) '{status:"timeout", wall_time_sec:$w, exit_code:124}' > "$out_dir/meta.json"
    echo "  [$topic_id/$mode/run$run_n] TIMEOUT"
  elif (( exit_code != 0 )); then
    jq -n --argjson w $((end-start)) --argjson e "$exit_code" '{status:"failed", wall_time_sec:$w, exit_code:$e}' > "$out_dir/meta.json"
    echo "  [$topic_id/$mode/run$run_n] FAILED ($exit_code)"
  else
    "$ROOT/collect_metrics.sh" "$out_dir" "$start" "$end"
    echo "  [$topic_id/$mode/run$run_n] OK $((end-start))s"
  fi
}

main() {
  preflight
  mkdir -p "$RUNS_DIR"

  local topic_ids
  if [[ -n "$ONLY_TOPIC" ]]; then
    topic_ids="$ONLY_TOPIC"
  else
    topic_ids=$(yq -r '.topics[].id' "$TOPICS")
  fi

  if (( ! REPORT_ONLY && ! JUDGE_ONLY )); then
    for topic_id in $topic_ids; do
      for mode in re baseline; do
        if [[ -n "$ONLY_MODE" && "$mode" != "$ONLY_MODE" ]]; then continue; fi
        for n in 1 2; do
          run_one "$topic_id" "$mode" "$n"
        done
      done
    done
  fi

  if (( ! NO_JUDGE && ! REPORT_ONLY )); then
    for topic_id in $topic_ids; do
      local td="$RUNS_DIR/$topic_id"
      if [[ -d "$td/re" && -d "$td/baseline" ]]; then
        python3 "$ROOT/judge.py" --topic-dir "$td" --topic-id "$topic_id" --judge-model "$JUDGE_MODEL" \
          || echo "  [judge $topic_id] FAILED — continuing"
      fi
    done
  fi

  # Aggregate (inline jq — no separate file needed for v1).
  local results="$RUNS_DIR/results.json"
  python3 - <<PY > "$results"
import json, os
from pathlib import Path
runs_dir = Path("$RUNS_DIR")
topics = []
for td in sorted(p for p in runs_dir.iterdir() if p.is_dir()):
    judge_path = td / "judge.json"
    j = json.loads(judge_path.read_text()) if judge_path.exists() else {}
    cm = j.get("cross_mode", {})
    repro = j.get("reproducibility", {})

    def block(mode):
        scores = dict(cm.get(mode, {}))
        scores.pop("rationale", None)
        scores["reproducibility"] = repro.get(mode)
        nums = [v for v in scores.values() if isinstance(v, (int, float))]
        weighted = round(sum(nums) * 10 / (len(nums) or 1), 2) if nums else None
        return {"scores": scores, "weighted_total": weighted}

    re_b, base_b = block("re"), block("baseline")
    delta = (re_b["weighted_total"] or 0) - (base_b["weighted_total"] or 0) if (re_b["weighted_total"] and base_b["weighted_total"]) else None
    topics.append({
        "id": td.name, "category": "?",
        "re": re_b, "baseline": base_b, "delta": delta,
        "judge_rationale": (cm.get("re", {}).get("rationale", "") + " | " + cm.get("baseline", {}).get("rationale", "")).strip(" |"),
    })

# Aggregate
def avg(xs):
    xs = [x for x in xs if x is not None]
    return round(sum(xs)/len(xs), 2) if xs else None
re_avg = avg([t["re"]["weighted_total"] for t in topics])
base_avg = avg([t["baseline"]["weighted_total"] for t in topics])
delta_avg = avg([t["delta"] for t in topics])
by_axis = {}
for axis in ("coverage","citation","depth","structure","reproducibility"):
    by_axis[axis] = {
        "re":       avg([t["re"]["scores"].get(axis) for t in topics]),
        "baseline": avg([t["baseline"]["scores"].get(axis) for t in topics]),
    }
print(json.dumps({
    "bench_date": "$DATE",
    "judge_model": "$JUDGE_MODEL",
    "model_under_test": os.environ.get("CLAUDE_MODEL", "default"),
    "topics": topics,
    "aggregate": {"re_avg": re_avg, "baseline_avg": base_avg, "delta_avg": delta_avg, "by_axis": by_axis, "by_category": {}},
}, indent=2, ensure_ascii=False))
PY

  python3 "$ROOT/report.py" --results "$results" --out "$RUNS_DIR/report.md"

  echo
  echo "✅ Bench complete. Report: $RUNS_DIR/report.md"
}

# Arg parsing
while (( $# > 0 )); do
  case "$1" in
    --check) preflight; exit $? ;;
    --topic) ONLY_TOPIC="$2"; shift 2 ;;
    --mode) ONLY_MODE="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --no-judge) NO_JUDGE=1; shift ;;
    --judge-only) JUDGE_ONLY=1; shift ;;
    --report-only) REPORT_ONLY=1; shift ;;
    --judge-model) JUDGE_MODEL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

main
```

- [ ] **Step 3: Re-run preflight test (must still pass)**

Run: `bats tests/bats/test_bench_run.bats`
Expected: all 3 tests still PASS.

- [ ] **Step 4: Delete spike notes**

```bash
rm bench/SPIKE-NOTES.md
```

- [ ] **Step 5: Commit**

```bash
git add bench/run.sh
git rm bench/SPIKE-NOTES.md
git commit -m "feat(bench): run.sh full matrix loop + judge dispatch + aggregate"
```

---

## Task 14: `/bench` Slash Command

**Files:**
- Create: `commands/bench.md`

- [ ] **Step 1: Write commands/bench.md**

```markdown
---
description: research-engine vs baseline mini-bench. Runs 5 topics × 2 modes × N=2, scores via LLM-as-judge, emits report.md with improvement opportunities.
argument-hint: "[--topic <id>] [--mode re|baseline] [--force] [--no-judge] [--judge-only] [--report-only] [--judge-model <m>] [--check]"
allowed-tools: Bash, Read
---

## Inputs

`$ARGUMENTS` is forwarded verbatim to `bench/run.sh`. See `bench/run.sh --help` for the full flag list.

## What this does

Runs the mini-bench described in `docs/superpowers/specs/2026-04-26-research-engine-bench-design.md`. Wall time for the full matrix is ~3 hours. Use `--topic smoke --no-judge` for a 1–2 minute plumbing smoke test before launching the real thing.

## Execution

Run:

```
bash "${CLAUDE_PLUGIN_ROOT}/bench/run.sh" $ARGUMENTS
```

Stream the output back to the user as it arrives. When the run finishes, point them to the final report path printed in the last `✅ Bench complete.` line. Do NOT post-process or summarize the report — the user inspects it directly.

If preflight fails (non-zero exit before any matrix run), surface the error verbatim and stop.
```

- [ ] **Step 2: Commit**

```bash
git add commands/bench.md
git commit -m "feat(bench): /bench slash command (thin entry to run.sh)"
```

---

## Task 15: End-to-End Smoke Test

**Goal:** Validate the entire pipeline against the smoke topic before spending 3+ hours on the full matrix. This is the manual acceptance gate.

- [ ] **Step 1: Run preflight only**

```bash
bench/run.sh --check
```

Expected: all `✓` lines, exit 0.

- [ ] **Step 2: Run smoke topic without judge**

```bash
bench/run.sh --topic smoke --no-judge
```

Expected:
- `bench/runs/<today>/smoke/re/run1/output.md` exists, non-empty
- `bench/runs/<today>/smoke/re/run2/output.md` exists, non-empty
- `bench/runs/<today>/smoke/baseline/run1/output.md` exists, non-empty
- `bench/runs/<today>/smoke/baseline/run2/output.md` exists, non-empty
- Each run has `meta.json` with `status: ok`
- Total time ~5–10 minutes for 4 short runs

- [ ] **Step 3: Re-run to verify idempotency**

```bash
bench/run.sh --topic smoke --no-judge
```

Expected: every run prints `[skip exists]`, no new output written.

- [ ] **Step 4: Run judge in dry-run on smoke**

```bash
bench/judge.py --dry-run \
  --topic-dir bench/runs/<today>/smoke \
  --topic-id smoke
```

Expected: prompt printed to stdout, `report A` and `report B` sections both present, no error.

- [ ] **Step 5: Run judge for real on smoke (validates Stage 4a + 4b)**

```bash
bench/judge.py \
  --topic-dir bench/runs/<today>/smoke \
  --topic-id smoke
```

Expected: `bench/runs/<today>/smoke/judge.json` exists, contains `cross_mode.re.coverage`, `cross_mode.baseline.coverage`, `reproducibility.re`, `reproducibility.baseline`.

- [ ] **Step 6: Run judge self-check**

```bash
bench/judge.py --self-check \
  --topic-dir bench/runs/<today>/smoke \
  --topic-id smoke-selfcheck
```

Inspect output: in self-check mode, both A and B were the same RE output, so the 4 axes should be within ~1 point of each other. If they diverge, the judge is biased on label position — fix the prompt before continuing.

- [ ] **Step 7: Generate report from smoke results only**

```bash
bench/run.sh --topic smoke --report-only
```

Expected: `bench/runs/<today>/report.md` exists, contains the smoke topic in the per-topic table.

- [ ] **Step 8: Manually inspect report.md**

Open `bench/runs/<today>/report.md`. Verify:
- Executive summary numbers look plausible
- Per-topic table renders
- Improvement opportunities section is present (even if just "no obvious weak spots")
- Limitations section is present

- [ ] **Step 9: Acceptance checklist file**

Create `tests/acceptance/bench.md`:

```markdown
# /bench acceptance checklist

Run before merging changes that touch bench code.

- [ ] `bench/run.sh --check` exits 0
- [ ] `bench/run.sh --topic smoke --no-judge` produces 4 outputs in 5–10 min
- [ ] Re-running the smoke command prints `[skip exists]` (idempotency)
- [ ] `bench/judge.py --self-check` returns axes within ~1 point of each other
- [ ] `bench/run.sh --topic smoke --report-only` writes report.md
- [ ] report.md contains: executive summary, per-topic table, improvement opportunities, limitations
- [ ] All bats tests pass: `bats tests/bats/test_collect_metrics.bats tests/bats/test_judge.bats tests/bats/test_report.bats tests/bats/test_bench_run.bats`
```

- [ ] **Step 10: Commit acceptance checklist**

```bash
git add tests/acceptance/bench.md
git commit -m "test(bench): acceptance checklist + smoke validated end-to-end"
```

---

## Task 16: Add 5 Production Topics

**Goal:** Append 5 concrete production topics to `bench/topics.yaml`. Each step requires the engineer to pick a real URL based on judgment — they are not pre-baked because that picking is itself a load-bearing choice for bench validity.

Selection criteria (apply to every category):
- **Stable**: not behind login/paywall, unlikely to disappear in 3–6 months
- **Representative**: a typical thing a research-engine user would actually feed it
- **Cheap-ish**: not a 2-hour video; not a 100-page paper

The fairness rule for `baseline_prompt` (already documented in topics.yaml header): only the keywords "deep research" + "구조화된 markdown" + "인용 포함" (or near-equivalents) may be shared with research-engine prompts. Any extra guidance leaks RE prompt design into the baseline.

- [ ] **Step 1: Pick a YouTube target and append entry**

Pick a 10–20 minute technical talk with manual captions (not a podcast, not a Short). Examples that fit: an Anthropic engineering talk, a paper-walkthrough video, a conference talk. Verify captions exist via `yt-dlp --list-subs <url>`.

Append to `bench/topics.yaml` (before the `# Smoke topic` line):

```yaml
  - id: youtube-<short-slug>
    category: youtube
    url: https://www.youtube.com/watch?v=<picked-id>
    baseline_prompt: |
      이 YouTube 영상에 대한 deep research 를 해줘. 핵심 주장, 인용, 한계점 포함한
      구조화된 markdown 리포트를 만들어줘: {url}
```

Replace `<short-slug>` with a stable slug (e.g., `youtube-harness-talk`) and `<picked-id>` with the chosen video id.

- [ ] **Step 2: Pick an arXiv target and append**

Pick a paper from the last ~6 months with a proper abstract and PDF, around 8–15 pages. Avoid survey papers (too broad) and workshop notes (too thin).

```yaml
  - id: arxiv-<slug>
    category: arxiv
    url: https://arxiv.org/abs/<picked-id>
    baseline_prompt: |
      이 논문에 대한 deep research 리포트를 만들어줘. 핵심 기여, 방법론, 인용 포함된
      구조화된 markdown 으로: {url}
```

- [ ] **Step 3: Pick a GitHub target and append**

Pick a real OSS project with README + recent commits, mid-size. Avoid awesome-lists and personal dotfiles. A popular framework or model-inference library is a good fit.

```yaml
  - id: github-<repo-slug>
    category: github
    url: https://github.com/<owner>/<repo>
    baseline_prompt: |
      이 GitHub 저장소를 분석해줘 — 목적, 구조, 활성도, 사용 사례. 인용 포함된
      구조화된 markdown 리포트로: {url}
```

- [ ] **Step 4: Pick a blog/docs target and append**

Pick a substantial engineering blog post or doc page, not a marketing landing. Anthropic engineering blog, Cloudflare blog, or a similarly meaty technical post.

```yaml
  - id: blog-<slug>
    category: blog
    url: https://<host>/<post>
    baseline_prompt: |
      이 블로그/문서 페이지에 대한 deep research. 핵심 주장, 인용, 한계점 포함한
      구조화된 markdown: {url}
```

- [ ] **Step 5: Pick a topic-only target and append**

Pick a moderately specific keyword phrase that has clear signal but isn't a single-link answer. E.g., "MoE LLM trends 2026" or "Mamba state-space model adoption". The `id` field stripped of its `topic-` prefix becomes the `{topic}` substitution.

```yaml
  - id: topic-<slug-derived-from-phrase>
    category: topic
    url: null
    baseline_prompt: |
      "{topic}" 에 대한 deep research 리포트를 만들어줘. 최신 동향, 주요 플레이어,
      인용 포함된 구조화된 markdown.
```

- [ ] **Step 6: Validate yaml parses and contains 6 topics**

```bash
yq '.topics | length' bench/topics.yaml
```

Expected output: `6`.

```bash
yq '.topics[].id' bench/topics.yaml
```

Expected: 6 ids (5 production + smoke).

- [ ] **Step 7: Commit**

```bash
git add bench/topics.yaml
git commit -m "chore(bench): add 5 production topics across all categories"
```

---

## Task 17: Run Full Matrix and Surface Improvements

**Goal:** Execute the bench end-to-end, read the resulting report, and capture a concrete list of improvement opportunities. Wall time ~3.3 hours.

- [ ] **Step 1: Verify environment one more time**

```bash
bench/run.sh --check
```

- [ ] **Step 2: Kick off the full matrix**

```bash
bench/run.sh
```

Streams progress per run. Expect 20 successful runs over ~3 hours. Partial failures are OK — the bench continues.

- [ ] **Step 3: Inspect report**

```bash
cat bench/runs/<today>/report.md
```

Read the **Improvement opportunities** section. Each entry there is a candidate for a follow-up issue/PR.

- [ ] **Step 4: File issues / log findings**

For each improvement opportunity:
- If actionable (clear root cause, specific adapter or stage), open a GitHub issue or note it in the next research-engine PR scope.
- If unclear (judge's rationale insufficient), mark for human review of the raw outputs before action.

- [ ] **Step 5: Commit findings (without raw run outputs)**

`bench/runs/<date>/` is `.gitignore`'d as a class (raw outputs are reproducible). Commit only the new artifacts that are useful as a permanent record:
- `bench/findings/<date>-summary.md` — distilled conclusions

```bash
mkdir -p bench/findings
# Write summary by hand based on report.md
git add bench/findings/<date>-summary.md
git commit -m "docs(bench): findings summary from <date> matrix run"
```

---

## Task 18: Docs + CHANGELOG + .gitignore

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `DEVELOPMENT.md`
- Modify: `.gitignore`

- [ ] **Step 1: Add `/bench` section to README.md**

Append (under the existing Usage block):

```markdown
### Bench mode

`/bench` runs a self-comparison harness: research-engine vs vanilla Claude Code (general-purpose subagent) on the same 5-topic set, scored by LLM-as-judge on 5 axes (Coverage / Citation / Depth / Structure / Reproducibility). Outputs land in `bench/runs/<date>/report.md` with an `Improvement opportunities` section.

```
/bench --check                          # preflight only
/bench --topic smoke --no-judge         # 1–2 min plumbing smoke
/bench                                  # full matrix (~3 hours)
/bench --topic <id> --force             # re-run a single topic
/bench --report-only                    # regenerate report from existing results.json
```

Spec: `docs/superpowers/specs/2026-04-26-research-engine-bench-design.md`.
```

- [ ] **Step 2: Add CHANGELOG entry**

Add a new section at the top of `CHANGELOG.md`:

```markdown
## [Unreleased]

### Added
- `/bench` slash command — repeatable mini-bench comparing research-engine vs Claude Code baseline on a 5-topic × 2-mode × N=2 matrix, with LLM-as-judge 5-axis rubric and improvement-opportunities report.
```

- [ ] **Step 3: Update DEVELOPMENT.md**

Note the new bats test files:

```markdown
### Bench tests

- `tests/bats/test_collect_metrics.bats`
- `tests/bats/test_judge.bats`
- `tests/bats/test_report.bats`
- `tests/bats/test_bench_run.bats`

Run all bench tests: `bats tests/bats/test_*.bats`
Manual acceptance: `tests/acceptance/bench.md`
```

- [ ] **Step 4: Add `bench/runs/` to .gitignore**

Append to `.gitignore`:

```
# bench raw outputs are reproducible — only design + harness + findings are committed.
bench/runs/
```

- [ ] **Step 5: Commit**

```bash
git add README.md CHANGELOG.md DEVELOPMENT.md .gitignore
git commit -m "docs(bench): /bench README + CHANGELOG + DEVELOPMENT entry; gitignore raw runs"
```

---

## Verification Summary

After all 18 tasks complete:

```bash
# All bats green
bats tests/bats/test_collect_metrics.bats tests/bats/test_judge.bats \
     tests/bats/test_report.bats tests/bats/test_bench_run.bats

# Slash command discoverable
ls commands/bench.md

# End-to-end smoke
bench/run.sh --topic smoke --no-judge

# Real bench has been run at least once
ls bench/runs/*/report.md

# Findings logged
ls bench/findings/
```
