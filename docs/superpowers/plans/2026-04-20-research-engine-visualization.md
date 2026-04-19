# research-engine Visualization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/research-visualize` slash command that produces data charts (QuickChart PNG, default), optional Mermaid diagrams, and optional Marp slide decks for an existing research session — leaving the main `/research` pipeline and adapter contract untouched.

**Architecture:** Post-hoc visualizer over completed `research/<slug>/` sessions. Four new shell scripts + four new subagent prompts + one orchestrator command. README is patched in a marker-bounded block for idempotent re-runs. All outputs land under the session directory.

**Tech Stack:** Bash + `jq` + `curl` + `python3` (stdlib) for extraction/rendering, `npx @marp-team/marp-cli` for slides (optional), Bats for unit tests, QuickChart.io HTTPS API for chart PNGs.

**Spec:** `docs/superpowers/specs/2026-04-20-research-engine-visualization-design.md`

---

## File Structure

### Create

| Path | Responsibility |
|---|---|
| `lib/chart_spec_contract.md` | Chart spec JSON schema (authored once, referenced by extractor prompt) |
| `agents/visualizer-extractor.md` | Subagent: reads README + sources.json, emits `charts[]` JSON |
| `agents/visualizer-diagrammer.md` | Subagent: emits `diagrams[]` JSON with mermaid text |
| `agents/visualizer-deck.md` | Subagent: emits Marp `slides.md` content |
| `scripts/load_session.sh` | Validate `<slug>`, emit JSON context `{slug, report_dir, readme, sources}` |
| `scripts/render_chart.sh` | Read chart spec JSON, call QuickChart, write PNG + `.meta.json` |
| `scripts/render_slides.sh` | Wrap `npx marp-cli` — given `slides.md` produce `.pptx`+`.pdf` |
| `scripts/patch_readme.sh` | Idempotent in-place replace of `<!-- viz:begin --> … <!-- viz:end -->` block |
| `commands/research-visualize.md` | Orchestrator: parses flags, runs stages, writes `viz.json` |
| `tests/bats/test_load_session.bats` | Unit test for load_session.sh |
| `tests/bats/test_patch_readme.bats` | Unit test for patch_readme.sh |
| `tests/bats/test_render_chart.bats` | Unit test for render_chart.sh (uses `--print-url` for HTTP-free tests) |
| `tests/fixtures/sample-session/README.md` | Minimal report with §TL;DR + §상세분석 containing numbers |
| `tests/fixtures/sample-session/sources.json` | Two sources |
| `tests/fixtures/sample-session/intent.json` | Mock intent |
| `tests/acceptance/research-visualize.md` | Manual acceptance checklist |

### Modify

| Path | Change |
|---|---|
| `README.md` | Add `/research-visualize` usage + optional `npx` dependency note |
| `CHANGELOG.md` | 0.3.0 entry (Added only) |
| `DEVELOPMENT.md` | Mention new bats files |

### Do not touch

`commands/research.md`, `commands/research-followup.md`, `agents/*-adapter.md`, `lib/adapter_contract.md`, `lib/report_sections.md`, `scripts/push_to_notion.sh`, `scripts/yt_fetch.sh`, `scripts/slugify.sh`, `scripts/classify_url.sh`, `scripts/cache_key.sh`, `scripts/find_latest_session.sh`.

---

## Task 1: Chart Spec Contract Document

**Files:**
- Create: `lib/chart_spec_contract.md`

- [ ] **Step 1: Write the full contract**

Create `lib/chart_spec_contract.md` with this content:

````markdown
# Chart Spec Contract

Produced by `agents/visualizer-extractor.md`. Consumed by `scripts/render_chart.sh`.

## Schema

```json
{
  "charts": [
    {
      "id": "c1",
      "title": "차트 제목 (리포트 언어)",
      "kind": "bar | line | pie | scatter | horizontal_bar | table",
      "rationale": "이 차트를 만든 이유 (한 문장)",
      "data": {
        "labels": ["항목A", "항목B", "..."],
        "datasets": [
          { "label": "시리즈 이름", "values": [1.0, 2.0, 3.0] }
        ]
      },
      "evidence": [
        { "source_id": 3, "quote_verbatim": "원문 인용 — 숫자 포함" }
      ],
      "axis": { "x": "x축 레이블", "y": "y축 레이블" }
    }
  ],
  "rejected": [
    { "reason": "왜 차트화하지 못했는지", "excerpt": "원문 일부" }
  ]
}
```

## Hard constraints (extractor MUST enforce)

1. Every number in any `datasets[].values[]` MUST appear as a substring of at least one `quote_verbatim` in the same chart's `evidence[]`. If not, reject that chart into `rejected[]`.
2. Every `evidence[].source_id` MUST be a positive integer present in the consuming session's `sources.json`.
3. Reject vague numerics ("약", "대략", "roughly", "~"). Quote the surrounding context verbatim — no paraphrase.
4. `charts[]` length ≤ 5. Empty is valid.
5. Per chart, total data points (Σ labels × datasets) ≤ 12.
6. `kind` MUST be one of the six listed. Any other value → reject chart.
7. For `kind: "scatter"`, `datasets[].values[]` is an array of `{x: number, y: number}` objects; otherwise plain numbers.

## Rendering (`scripts/render_chart.sh`)

Maps the spec to a Chart.js v4 config and calls QuickChart.io:

- `bar`            → `{ type: "bar", data, options: { scales: {...} } }`
- `horizontal_bar` → `{ type: "bar", ..., options: { indexAxis: "y" } }`
- `line`           → `{ type: "line", ..., options: { elements: { line: { tension: 0.2 } } } }`
- `pie`            → `{ type: "pie", data }`
- `scatter`        → `{ type: "scatter", data }`
- `table`          → QuickChart `chart: "table"` via the `/chart?c=...` table variant

URL form: `https://quickchart.io/chart?c=<url-encoded>&width=800&height=400&backgroundColor=white&version=4`

## Meta sidecar

For each rendered chart, write `figures/chart-NN-<slug>.meta.json` with `{id, title, spec, rendered_at, quickchart_url, source_ids}` so the chart is fully reconstructible without re-running the extractor.
````

- [ ] **Step 2: Commit**

```bash
git add lib/chart_spec_contract.md
git commit -m "docs: add chart spec contract for visualizer extractor"
```

---

## Task 2: Test Fixture (sample-session)

**Files:**
- Create: `tests/fixtures/sample-session/README.md`
- Create: `tests/fixtures/sample-session/sources.json`
- Create: `tests/fixtures/sample-session/intent.json`

- [ ] **Step 1: Write README.md**

Create `tests/fixtures/sample-session/README.md`:

```markdown
---
title: "샘플 세션"
slug: "sample-session"
created: "2026-04-20T00:00:00Z"
input: "sample"
input_type: "topic"
intent_mode: "assumed"
---

## 요약 (TL;DR)

테스트 픽스처. Model A 88.7, Model B 91.2, Model C 86.4, Model D 82.1 의 MMLU 점수를 비교.

## 핵심 포인트

- Model B 가 MMLU 91.2 % 로 최고 [2]
- Model A 는 88.7 % 로 2위 [1]

## 상세 분석

### 벤치마크 비교

Model A 는 MMLU 에서 88.7 점을 기록했다 [1]. Model B 는 91.2 점 [2]. Model C 는 86.4 점 [1]. Model D 는 82.1 점 [2].

## Sources

1. **Paper A** — https://example.com/a (adapter: `arxiv`, fetched: 2026-04-20T00:00:00Z)
2. **Paper B** — https://example.com/b (adapter: `arxiv`, fetched: 2026-04-20T00:00:00Z)
```

- [ ] **Step 2: Write sources.json**

Create `tests/fixtures/sample-session/sources.json`:

```json
{
  "sources": [
    { "n": 1, "adapter": "arxiv", "type": "arxiv-paper", "url": "https://example.com/a", "title": "Paper A", "meta": {}, "fetched_at": "2026-04-20T00:00:00Z" },
    { "n": 2, "adapter": "arxiv", "type": "arxiv-paper", "url": "https://example.com/b", "title": "Paper B", "meta": {}, "fetched_at": "2026-04-20T00:00:00Z" }
  ],
  "intent": { "purpose": "학습", "focus": "벤치마크 비교", "audience_level": "초보" },
  "input": "sample",
  "input_type": "topic",
  "created": "2026-04-20T00:00:00Z"
}
```

- [ ] **Step 3: Write intent.json**

Create `tests/fixtures/sample-session/intent.json`:

```json
{ "purpose": "학습", "focus": "벤치마크 비교", "audience_level": "초보", "notes": "fixture" }
```

- [ ] **Step 4: Commit**

```bash
git add tests/fixtures/sample-session/
git commit -m "test: add sample-session fixture for visualizer tests"
```

---

## Task 3: `scripts/load_session.sh` (TDD)

**Files:**
- Create: `scripts/load_session.sh`
- Test: `tests/bats/test_load_session.bats`

- [ ] **Step 1: Write failing tests**

Create `tests/bats/test_load_session.bats`:

```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/load_session.sh"
FIXTURE="$BATS_TEST_DIRNAME/../fixtures/sample-session"

@test "fails when research dir missing" {
  run "$SCRIPT" "sample-session" "/nonexistent/research"
  [ "$status" -ne 0 ]
}

@test "fails when slug dir missing" {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/research"
  run "$SCRIPT" "ghost" "$tmp/research"
  [ "$status" -ne 0 ]
  rm -rf "$tmp"
}

@test "fails when README.md missing" {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/research/x"
  echo '{}' > "$tmp/research/x/sources.json"
  run "$SCRIPT" "x" "$tmp/research"
  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
  rm -rf "$tmp"
}

@test "fails when sources.json missing" {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/research/x"
  echo '# ok' > "$tmp/research/x/README.md"
  run "$SCRIPT" "x" "$tmp/research"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sources.json"* ]]
  rm -rf "$tmp"
}

@test "emits JSON with slug, report_dir, readme, sources for valid session" {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/research"
  cp -r "$FIXTURE" "$tmp/research/sample-session"
  run "$SCRIPT" "sample-session" "$tmp/research"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.slug == "sample-session"' >/dev/null
  echo "$output" | jq -e '.report_dir | endswith("/sample-session")' >/dev/null
  echo "$output" | jq -e '.readme | contains("벤치마크")' >/dev/null
  echo "$output" | jq -e '.sources | length == 2' >/dev/null
  rm -rf "$tmp"
}
```

- [ ] **Step 2: Run tests, verify all FAIL**

```bash
cd /home/taejin/projects/research-engine
bats tests/bats/test_load_session.bats
```

Expected: all 5 fail (script does not exist).

- [ ] **Step 3: Write load_session.sh**

Create `scripts/load_session.sh`:

```bash
#!/usr/bin/env bash
# Validate <slug>'s session dir under <research_dir>.
# Emit JSON { slug, report_dir, readme, sources } on stdout.
# Usage: load_session.sh <slug> <research_dir>
set -euo pipefail

slug="${1:-}"
root="${2:-}"

[[ -n "$slug" ]] || { echo "load_session: slug required" >&2; exit 2; }
[[ -d "$root" ]] || { echo "load_session: no research dir: $root" >&2; exit 1; }

report_dir="$root/$slug"
[[ -d "$report_dir" ]] || { echo "load_session: no session dir: $report_dir" >&2; exit 1; }

readme="$report_dir/README.md"
[[ -f "$readme" ]] || { echo "load_session: missing README.md in $report_dir" >&2; exit 1; }

sources="$report_dir/sources.json"
[[ -f "$sources" ]] || { echo "load_session: missing sources.json in $report_dir" >&2; exit 1; }

jq -n \
  --arg slug "$slug" \
  --arg dir "$report_dir" \
  --rawfile readme "$readme" \
  --slurpfile src "$sources" \
  '{slug: $slug, report_dir: $dir, readme: $readme, sources: $src[0].sources}'
```

Make executable:

```bash
chmod +x scripts/load_session.sh
```

- [ ] **Step 4: Run tests, verify all PASS**

```bash
bats tests/bats/test_load_session.bats
```

Expected: all 5 pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/load_session.sh tests/bats/test_load_session.bats
git commit -m "feat(scripts): add load_session.sh for visualizer input assembly"
```

---

## Task 4: `scripts/patch_readme.sh` (TDD)

**Files:**
- Create: `scripts/patch_readme.sh`
- Test: `tests/bats/test_patch_readme.bats`

Behavior: given an existing `README.md` path and a content file, replace the block delimited by `<!-- viz:begin -->` and `<!-- viz:end -->`. If markers not present, append the block just before `## Sources` (or end of file if no Sources section). Idempotent.

- [ ] **Step 1: Write failing tests**

Create `tests/bats/test_patch_readme.bats`:

```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/patch_readme.sh"

setup() {
  TMPDIR_T="$(mktemp -d)"
  README="$TMPDIR_T/README.md"
  BLOCK="$TMPDIR_T/block.md"
  cat > "$BLOCK" <<'EOF'
## 시각 자료

![chart](figures/chart-01-x.png)
EOF
}

teardown() { rm -rf "$TMPDIR_T"; }

@test "appends before ## Sources when markers absent" {
  cat > "$README" <<'EOF'
# Title

body

## Sources

1. foo
EOF
  run "$SCRIPT" "$README" "$BLOCK"
  [ "$status" -eq 0 ]
  run grep -c '<!-- viz:begin -->' "$README"
  [ "$output" = "1" ]
  run grep -c '<!-- viz:end -->' "$README"
  [ "$output" = "1" ]
  # viz block must precede Sources
  python3 - "$README" <<'PY'
import sys
text = open(sys.argv[1]).read()
b = text.index('<!-- viz:begin -->')
s = text.index('## Sources')
assert b < s, f"viz block not before Sources: {b} >= {s}"
PY
}

@test "appends at end when no ## Sources section exists" {
  cat > "$README" <<'EOF'
# Title

just body, no sources
EOF
  run "$SCRIPT" "$README" "$BLOCK"
  [ "$status" -eq 0 ]
  run tail -n1 "$README"
  [ "$output" = "<!-- viz:end -->" ]
}

@test "replaces in-place when markers present" {
  cat > "$README" <<'EOF'
# Title

<!-- viz:begin -->
## 시각 자료 OLD
OLD BODY
<!-- viz:end -->

## Sources

1. foo
EOF
  run "$SCRIPT" "$README" "$BLOCK"
  [ "$status" -eq 0 ]
  ! grep -q 'OLD BODY' "$README"
  grep -q 'chart-01-x.png' "$README"
  # exactly one pair of markers
  [ "$(grep -c '<!-- viz:begin -->' "$README")" = "1" ]
  [ "$(grep -c '<!-- viz:end -->' "$README")" = "1" ]
}

@test "idempotent: running twice produces identical file" {
  cat > "$README" <<'EOF'
# Title

body

## Sources

1. foo
EOF
  "$SCRIPT" "$README" "$BLOCK"
  cp "$README" "$TMPDIR_T/after1.md"
  "$SCRIPT" "$README" "$BLOCK"
  run diff "$TMPDIR_T/after1.md" "$README"
  [ "$status" -eq 0 ]
}

@test "does not modify non-marker text" {
  cat > "$README" <<'EOF'
# Title

body line A
body line B

<!-- viz:begin -->
old block
<!-- viz:end -->

tail line
EOF
  "$SCRIPT" "$README" "$BLOCK"
  grep -q 'body line A' "$README"
  grep -q 'body line B' "$README"
  grep -q 'tail line' "$README"
}

@test "fails when README missing" {
  run "$SCRIPT" "$TMPDIR_T/ghost.md" "$BLOCK"
  [ "$status" -ne 0 ]
}

@test "fails when block file missing" {
  cat > "$README" <<< "# t"
  run "$SCRIPT" "$README" "$TMPDIR_T/ghost.md"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run tests, verify all FAIL**

```bash
bats tests/bats/test_patch_readme.bats
```

Expected: all 7 fail.

- [ ] **Step 3: Write patch_readme.sh**

Create `scripts/patch_readme.sh`:

```bash
#!/usr/bin/env bash
# Replace the <!-- viz:begin --> ... <!-- viz:end --> block in README.md with the
# contents of <block_file>. If markers are absent, insert before "## Sources"
# section (or append to end if no such section). Idempotent.
#
# Usage: patch_readme.sh <readme.md> <block_file>
set -euo pipefail

readme="${1:-}"
block_file="${2:-}"

[[ -f "$readme" ]]     || { echo "patch_readme: README not found: $readme" >&2; exit 1; }
[[ -f "$block_file" ]] || { echo "patch_readme: block file not found: $block_file" >&2; exit 1; }

python3 - "$readme" "$block_file" <<'PY'
import io, sys, re, pathlib

readme_path = pathlib.Path(sys.argv[1])
block_path  = pathlib.Path(sys.argv[2])

text  = readme_path.read_text(encoding="utf-8")
block_body = block_path.read_text(encoding="utf-8").rstrip("\n")
wrapped = f"<!-- viz:begin -->\n{block_body}\n<!-- viz:end -->"

begin = "<!-- viz:begin -->"
end   = "<!-- viz:end -->"

if begin in text and end in text:
    # Replace marker-bounded block in place.
    pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.DOTALL)
    new_text = pattern.sub(wrapped, text, count=1)
else:
    # Insert before "## Sources" line, else append to end.
    sources_re = re.compile(r"^## Sources\s*$", re.MULTILINE)
    m = sources_re.search(text)
    if m:
        insert_at = m.start()
        # Leave blank line buffer above and below.
        prefix = text[:insert_at].rstrip("\n") + "\n\n"
        suffix = "\n\n" + text[insert_at:]
        new_text = prefix + wrapped + suffix
    else:
        trimmed = text.rstrip("\n")
        new_text = trimmed + "\n\n" + wrapped + "\n"

# Only write if changed (keeps mtime stable for no-op reruns).
if new_text != text:
    readme_path.write_text(new_text, encoding="utf-8")
PY
```

Make executable:

```bash
chmod +x scripts/patch_readme.sh
```

- [ ] **Step 4: Run tests, verify all PASS**

```bash
bats tests/bats/test_patch_readme.bats
```

Expected: all 7 pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/patch_readme.sh tests/bats/test_patch_readme.bats
git commit -m "feat(scripts): add patch_readme.sh with marker-based idempotent replace"
```

---

## Task 5: `scripts/render_chart.sh` (TDD)

**Files:**
- Create: `scripts/render_chart.sh`
- Test: `tests/bats/test_render_chart.bats`

Behavior:
- Input: chart-spec JSON path, output PNG path.
- Validates spec with `jq` (evidence present, values in quotes, kind in allowed set).
- `--print-url` mode: emits the QuickChart URL to stdout and exits 0 (no network) — for testing.
- Normal mode: calls `curl -fsSL <url> -o <out.png>`, writes `<out>.meta.json` next to it.
- On validation failure: exit 3, write to stderr.
- On curl failure: exit 4, leave no partial files.

- [ ] **Step 1: Write failing tests**

Create `tests/bats/test_render_chart.bats`:

```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/render_chart.sh"

setup() {
  TMPDIR_T="$(mktemp -d)"
  SPEC="$TMPDIR_T/spec.json"
  OUT="$TMPDIR_T/chart.png"
}

teardown() { rm -rf "$TMPDIR_T"; }

valid_spec() {
  cat > "$SPEC" <<'EOF'
{
  "id": "c1",
  "title": "MMLU 비교",
  "kind": "bar",
  "rationale": "테스트용",
  "data": {
    "labels": ["A", "B"],
    "datasets": [ { "label": "MMLU", "values": [88.7, 91.2] } ]
  },
  "evidence": [
    { "source_id": 1, "quote_verbatim": "A scored 88.7 on MMLU" },
    { "source_id": 2, "quote_verbatim": "B scored 91.2 on MMLU" }
  ],
  "axis": { "x": "모델", "y": "점수" }
}
EOF
}

@test "--print-url emits a quickchart URL for valid spec" {
  valid_spec
  run "$SCRIPT" --print-url "$SPEC"
  [ "$status" -eq 0 ]
  [[ "$output" == https://quickchart.io/chart?c=* ]]
  [[ "$output" == *"width=800"* ]]
}

@test "rejects spec with missing evidence" {
  cat > "$SPEC" <<'EOF'
{ "id": "c1", "title": "x", "kind": "bar",
  "data": { "labels": ["A"], "datasets": [ { "label": "s", "values": [5] } ] },
  "evidence": [] }
EOF
  run "$SCRIPT" --print-url "$SPEC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"evidence"* ]]
}

@test "rejects spec with number not in any evidence quote" {
  cat > "$SPEC" <<'EOF'
{ "id": "c1", "title": "x", "kind": "bar",
  "data": { "labels": ["A"], "datasets": [ { "label": "s", "values": [99.9] } ] },
  "evidence": [ { "source_id": 1, "quote_verbatim": "completely different text" } ] }
EOF
  run "$SCRIPT" --print-url "$SPEC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"99.9"* ]]
}

@test "rejects spec with disallowed kind" {
  cat > "$SPEC" <<'EOF'
{ "id": "c1", "title": "x", "kind": "bogus",
  "data": { "labels": ["A"], "datasets": [ { "label": "s", "values": [1] } ] },
  "evidence": [ { "source_id": 1, "quote_verbatim": "1" } ] }
EOF
  run "$SCRIPT" --print-url "$SPEC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"kind"* ]]
}

@test "horizontal_bar produces bar type with indexAxis=y" {
  cat > "$SPEC" <<'EOF'
{ "id": "c1", "title": "x", "kind": "horizontal_bar",
  "data": { "labels": ["A"], "datasets": [ { "label": "s", "values": [1.0] } ] },
  "evidence": [ { "source_id": 1, "quote_verbatim": "1.0" } ] }
EOF
  run "$SCRIPT" --print-url "$SPEC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"indexAxis"* ]]
}

@test "fails when spec file missing" {
  run "$SCRIPT" --print-url "/nonexistent/spec.json"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run tests, verify all FAIL**

```bash
bats tests/bats/test_render_chart.bats
```

Expected: all 6 fail.

- [ ] **Step 3: Write render_chart.sh**

Create `scripts/render_chart.sh`:

```bash
#!/usr/bin/env bash
# Render a chart-spec JSON via QuickChart.io.
#
# Usage:
#   render_chart.sh <spec.json> <out.png>         # fetch PNG + write <out>.meta.json
#   render_chart.sh --print-url <spec.json>       # print constructed URL, exit 0
#
# Exit codes: 0 ok · 2 bad args · 3 validation failed · 4 HTTP/curl failed
set -euo pipefail

print_url_only=0
if [[ "${1:-}" == "--print-url" ]]; then
  print_url_only=1
  shift
fi

spec="${1:-}"
out="${2:-}"

[[ -f "$spec" ]] || { echo "render_chart: spec not found: $spec" >&2; exit 2; }
if [[ "$print_url_only" -eq 0 ]]; then
  [[ -n "$out" ]] || { echo "render_chart: out path required" >&2; exit 2; }
fi

# Build the Chart.js config + URL via python (jq-only JSON construction for nested
# objects gets verbose). Echoes URL on stdout; also sets $SPEC_ID and $SOURCE_IDS
# via a pseudo-dotenv on stderr descriptor 3 when not in --print-url mode.
url=$(python3 - "$spec" <<'PY'
import json, sys, urllib.parse, re

spec_path = sys.argv[1]
with open(spec_path, "r", encoding="utf-8") as f:
    spec = json.load(f)

errors = []

allowed_kinds = {"bar", "line", "pie", "scatter", "horizontal_bar", "table"}
kind = spec.get("kind")
if kind not in allowed_kinds:
    errors.append(f"kind must be one of {sorted(allowed_kinds)}, got {kind!r}")

ev = spec.get("evidence") or []
if not ev:
    errors.append("evidence[] is empty")

# Collect values and assert each appears as a substring of some evidence quote.
data = spec.get("data") or {}
datasets = data.get("datasets") or []
quotes = " ||| ".join(e.get("quote_verbatim", "") for e in ev)
for ds in datasets:
    for v in ds.get("values", []):
        if isinstance(v, dict):  # scatter {x,y}
            nums = [v.get("x"), v.get("y")]
        else:
            nums = [v]
        for n in nums:
            if n is None:
                continue
            s = ("{:g}".format(n)) if isinstance(n, (int, float)) else str(n)
            if s not in quotes:
                # Try stringified float as-is too.
                if str(n) not in quotes:
                    errors.append(f"value {n!r} not found in any evidence quote_verbatim")

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(3)

# Build Chart.js config.
if kind == "horizontal_bar":
    cfg = { "type": "bar",
            "data": data,
            "options": { "indexAxis": "y",
                         "plugins": { "title": { "display": True, "text": spec.get("title","") } } } }
elif kind == "line":
    cfg = { "type": "line",
            "data": data,
            "options": { "elements": { "line": { "tension": 0.2 } },
                         "plugins": { "title": { "display": True, "text": spec.get("title","") } } } }
elif kind == "pie":
    cfg = { "type": "pie", "data": data,
            "options": { "plugins": { "title": { "display": True, "text": spec.get("title","") } } } }
elif kind == "scatter":
    cfg = { "type": "scatter", "data": data,
            "options": { "plugins": { "title": { "display": True, "text": spec.get("title","") } } } }
elif kind == "table":
    cfg = { "type": "table", "data": data, "options": { "title": spec.get("title","") } }
else:  # bar
    cfg = { "type": "bar", "data": data,
            "options": { "plugins": { "title": { "display": True, "text": spec.get("title","") } } } }

encoded = urllib.parse.quote(json.dumps(cfg, ensure_ascii=False), safe="")
print(f"https://quickchart.io/chart?c={encoded}&width=800&height=400&backgroundColor=white&version=4")
PY
)

if [[ "$print_url_only" -eq 1 ]]; then
  echo "$url"
  exit 0
fi

# Fetch the PNG.
tmp="$(mktemp)"
if ! curl -fsSL --max-time 30 "$url" -o "$tmp"; then
  rm -f "$tmp"
  echo "render_chart: HTTP/curl failed for $url" >&2
  exit 4
fi
mkdir -p "$(dirname "$out")"
mv "$tmp" "$out"

# Write meta sidecar.
meta="${out%.png}.meta.json"
python3 - "$spec" "$url" "$meta" <<'PY'
import json, sys, pathlib, datetime
spec  = json.load(open(sys.argv[1], "r", encoding="utf-8"))
url   = sys.argv[2]
meta  = pathlib.Path(sys.argv[3])
out = {
    "id": spec.get("id"),
    "title": spec.get("title"),
    "spec": spec,
    "rendered_at": datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z",
    "quickchart_url": url,
    "source_ids": sorted({ e.get("source_id") for e in (spec.get("evidence") or []) if e.get("source_id") is not None }),
}
meta.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
PY

echo "$out"
```

Make executable:

```bash
chmod +x scripts/render_chart.sh
```

- [ ] **Step 4: Run tests, verify all PASS**

```bash
bats tests/bats/test_render_chart.bats
```

Expected: all 6 pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/render_chart.sh tests/bats/test_render_chart.bats
git commit -m "feat(scripts): add render_chart.sh backed by QuickChart"
```

---

## Task 6: `scripts/render_slides.sh`

**Files:**
- Create: `scripts/render_slides.sh`

Thin wrapper: no unit test (hits external `npx`). Covered by manual acceptance.

- [ ] **Step 1: Write render_slides.sh**

Create `scripts/render_slides.sh`:

```bash
#!/usr/bin/env bash
# Render a Marp slides.md to .pptx and .pdf. On any failure, leave slides.md
# untouched and exit non-zero — the orchestrator treats this as non-fatal.
#
# Usage: render_slides.sh <slides.md>
set -euo pipefail

slides="${1:-}"
[[ -f "$slides" ]] || { echo "render_slides: slides.md not found: $slides" >&2; exit 1; }

dir="$(dirname "$slides")"

if ! command -v npx >/dev/null 2>&1; then
  echo "render_slides: npx not on PATH — install Node 18+. slides.md kept as-is." >&2
  exit 2
fi

# --allow-local-files is required so Marp can read figures/*.png referenced with
# relative paths. --html is off by default; we request pptx+pdf explicitly.
cd "$dir"
if ! npx --yes @marp-team/marp-cli@latest "$(basename "$slides")" \
       --pptx --pdf --allow-local-files; then
  echo "render_slides: marp-cli failed (network? node version?). slides.md kept." >&2
  exit 3
fi

echo "slides rendered: $dir/slides.pptx + $dir/slides.pdf"
```

Make executable:

```bash
chmod +x scripts/render_slides.sh
```

- [ ] **Step 2: Smoke test**

Run with a missing file to verify arg handling:

```bash
./scripts/render_slides.sh /nonexistent
```

Expected: exit 1 with "slides.md not found".

- [ ] **Step 3: Commit**

```bash
git add scripts/render_slides.sh
git commit -m "feat(scripts): add render_slides.sh marp-cli wrapper"
```

---

## Task 7: `agents/visualizer-extractor.md`

**Files:**
- Create: `agents/visualizer-extractor.md`

- [ ] **Step 1: Write the subagent prompt**

Create `agents/visualizer-extractor.md`:

````markdown
---
name: visualizer-extractor
description: Extract chartable numeric data from a completed research report and emit chart-spec JSON per lib/chart_spec_contract.md.
model: sonnet
---

You are the **visualizer-extractor**. Given a completed research session's README + sources, produce a JSON block listing up to 5 charts (bar/line/pie/scatter/horizontal_bar/table). Every value you chart must be anchored to a verbatim quote from the report text with a valid `source_id`.

## Inputs

A JSON object with:
- `readme` — full `README.md` text (markdown).
- `sources` — array of `{n, adapter, type, url, title, meta, fetched_at}` from `sources.json`.
- `slug`, `report_dir` — for context.

## Tools

- `Read` — you may re-read files under `report_dir/` if needed (e.g., transcript.md).
- No web tools. Do not invent data. Do not paraphrase numbers.

## Process

1. Skim the README for comparison/benchmark tables, lists of paired numbers, time series (dates + metrics), or rate/percentage clusters.
2. For each candidate cluster:
   a. Decide which `kind` fits: exactly 2 numeric dimensions with labels → `bar` or `horizontal_bar`; time/x-axis continuity → `line`; whole-of-total ≤ 6 slices → `pie`; paired (x,y) without labels → `scatter`; many rows × many cols → `table`.
   b. For each number you plan to chart, locate the passage in `readme` that contains that number as a substring. Copy that passage verbatim (sentence or fragment) into `evidence[].quote_verbatim`. Use the `[n]` marker from the passage to set `source_id` — the integer must exist in `sources`.
   c. If a number has no verbatim anchor, **do not** include it. Move the chart to `rejected[]` if you cannot assemble a valid evidence set.
3. Stop at 5 charts. Prefer high-salience charts (mentioned in §TL;DR or §핵심 포인트) over peripheral ones.
4. Emit a single fenced JSON block per `lib/chart_spec_contract.md`.

## Hard rules

- Numbers in `datasets[].values[]` MUST appear as substrings of the joined `evidence[].quote_verbatim` for the same chart.
- No "approximately", "around", "약", "roughly" — quote the context verbatim. If the number is presented with qualifiers, either include the qualified text in the quote or skip.
- `kind` ∈ {bar, line, pie, scatter, horizontal_bar, table}.
- Max 5 charts. Per chart ≤ 12 data points.
- Output `charts: []` and `rejected: [...]` if nothing qualifies — this is valid.

## Output envelope

```json
{
  "charts": [ ... ],
  "rejected": [ ... ]
}
```

No prose before or after the fenced block. The orchestrator parses the first fenced `json` block.
````

- [ ] **Step 2: Commit**

```bash
git add agents/visualizer-extractor.md
git commit -m "feat(agents): add visualizer-extractor subagent for chart specs"
```

---

## Task 8: `agents/visualizer-diagrammer.md`

**Files:**
- Create: `agents/visualizer-diagrammer.md`

- [ ] **Step 1: Write the subagent prompt**

Create `agents/visualizer-diagrammer.md`:

````markdown
---
name: visualizer-diagrammer
description: Emit Mermaid diagrams summarizing structural/flow/timeline content from a completed research report.
model: sonnet
---

You are the **visualizer-diagrammer**. Given a completed research session's README + sources, produce up to 3 Mermaid diagrams that summarize structure, flow, comparison hierarchy, timelines, or sequences.

## Inputs

Same JSON shape as visualizer-extractor: `{ readme, sources, slug, report_dir }`.

## Tools

- `Read` — you may re-read files under `report_dir/`.
- No web tools.

## Allowed Mermaid diagram kinds

- `flowchart` (LR or TD) — steps, decisions, branches
- `sequenceDiagram` — request/response, actor interactions
- `classDiagram` — type/component relationships
- `timeline` — dated milestones
- `gantt` — dated durations

Any other diagram kind → reject.

## Process

1. Read §요약, §핵심 포인트, §상세 분석. Identify 0–3 conceptual structures that genuinely benefit from a diagram vs. a bullet list.
2. For each, pick the matching Mermaid kind. Keep labels short (≤ 20 chars per node).
3. Set `placement` to guide README patching: `"after_section:<heading>"` where `<heading>` matches an existing README heading exactly (e.g., `"after_section:## 상세 분석"`), or `"end"` for the tail of the viz block.
4. Collect `evidence_src_ids` — the integer source ids the diagram's facts are drawn from (must exist in `sources`).

## Hard rules

- Each diagram's `mermaid` field is a single string starting with one of the allowed kind keywords.
- No HTML, no `click` handlers, no external URLs.
- Max 3 diagrams. Output `diagrams: []` if nothing warrants one.

## Output envelope

```json
{
  "diagrams": [
    {
      "id": "d1",
      "title": "...",
      "placement": "after_section:## 상세 분석",
      "mermaid": "flowchart LR\n  A[User] --> B{Decision}\n  B -->|yes| C[Path 1]\n  B -->|no|  D[Path 2]",
      "evidence_src_ids": [1, 3]
    }
  ]
}
```

No prose before or after the fenced block.
````

- [ ] **Step 2: Commit**

```bash
git add agents/visualizer-diagrammer.md
git commit -m "feat(agents): add visualizer-diagrammer subagent for mermaid diagrams"
```

---

## Task 9: `agents/visualizer-deck.md`

**Files:**
- Create: `agents/visualizer-deck.md`

- [ ] **Step 1: Write the subagent prompt**

Create `agents/visualizer-deck.md`:

````markdown
---
name: visualizer-deck
description: Generate a Marp markdown slide deck (slides.md) summarizing a completed research session.
model: sonnet
---

You are the **visualizer-deck**. Given a completed research session's README + sources + list of already-rendered chart files, produce the full contents of `slides.md` in Marp markdown format. The orchestrator will then call `render_slides.sh` to produce `.pptx` + `.pdf`.

## Inputs

A JSON object with:
- `readme` — full README.md.
- `sources` — array from sources.json.
- `charts` — array of `{ id, title, png_rel_path }` for already-rendered charts (rel path from slides.md, i.e., `figures/chart-01-<slug>.png`).
- `diagrams` — array of `{ id, title, mermaid }` (may be empty if `--diagrams` not passed).
- `slug`, `report_title`, `iso_date`.

## Output

Emit the **full contents of slides.md** as a single fenced code block with language `markdown`. No prose around it.

## Deck structure (in order)

1. **Title slide** — `# {{report_title}}` + italic slug + date.
2. **TL;DR slide** — extract 3–5 bullets from the README's §요약 (TL;DR).
3. **핵심 포인트 slides** — 1 to 3 slides, ≤ 6 bullets each, drawn from §핵심 포인트.
4. **Section summary slides** — up to 10 slides, one per subsection of §상세 분석. Title = subsection heading. Body = 2–4 bullets.
5. **Chart slides** — one slide per entry in `charts`: use `![bg fit]({{png_rel_path}})` so the image fills the slide. Put the chart title as a bottom caption via `<!-- _footer: ... -->` Marp directive.
6. **Diagram slides** — one per entry in `diagrams`: render the mermaid inside a fenced ` ```mermaid ` block.
7. **Sources slide** — numbered list from `sources` (title — url).

## Frontmatter (required)

```markdown
---
marp: true
theme: default
paginate: true
---
```

## Hard rules

- Use `---` between slides. No extraneous horizontal rules inside slides.
- Source language: match the README (Korean if that's the report language).
- No external image URLs — only `figures/...` paths from `charts`.
- Keep under 25 slides total.

## Output

A single fenced block:

````
```markdown
---
marp: true
...
```
````

No prose outside the block.
````

- [ ] **Step 2: Commit**

```bash
git add agents/visualizer-deck.md
git commit -m "feat(agents): add visualizer-deck subagent for marp slides"
```

---

## Task 10: `commands/research-visualize.md` (orchestrator)

**Files:**
- Create: `commands/research-visualize.md`

- [ ] **Step 1: Write the orchestrator command**

Create `commands/research-visualize.md`:

````markdown
---
description: Generate charts, optional Mermaid diagrams, and optional Marp slides for an existing research session.
argument-hint: "[<slug>] [--slides] [--diagrams] [--fresh]"
allowed-tools: Bash, Read, Write, Edit, Agent, Glob, Grep
---

## Inputs

`$ARGUMENTS` — parse:
- positional `slug` (optional; if absent, use the most recent session)
- `--slides` — also generate `slides.md` + `.pptx` + `.pdf`
- `--diagrams` — also generate Mermaid diagrams in the README viz block
- `--fresh` — wipe and regenerate `figures/`, `slides.*`, and replace the README viz block

## Constants

- `${CLAUDE_PLUGIN_ROOT}` = plugin root (exported by Claude Code)
- `RESEARCH_DIR` = `<project_cwd>/research`

## Pipeline

### Stage V1 — Resolve slug & load session

- If `slug` is empty: `slug=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/find_latest_session.sh" "$RESEARCH_DIR")`.
- Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/load_session.sh" "$slug" "$RESEARCH_DIR"`. Capture stdout as `SESSION_JSON`. On failure, abort with the script's error.
- Derive `report_dir="$RESEARCH_DIR/$slug"`.

### Stage V2 — Handle --fresh

If `--fresh`:
- `rm -rf "$report_dir/figures"` and `rm -f "$report_dir/slides.md" "$report_dir/slides.pptx" "$report_dir/slides.pdf"`.
- Leave the existing marker block in README.md in place. Stage V6 below will overwrite its contents via `patch_readme.sh`. If Stage V6 ends up with empty content (no charts AND no diagrams), use a small Python one-liner to strip the marker block entirely:

```bash
python3 -c '
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t2 = re.sub(r"\n*<!-- viz:begin -->.*?<!-- viz:end -->\n*", "\n\n", t, count=1, flags=re.DOTALL)
p.write_text(t2, encoding="utf-8")
' "$report_dir/README.md"
```

### Stage V3 — Extract charts (always)

Dispatch `agents/visualizer-extractor.md` as a single Agent call:

```
You are dispatched as visualizer-extractor.
Inputs: <JSON of {readme, sources, slug, report_dir}>

Return a single fenced JSON block per lib/chart_spec_contract.md.
```

Parse the first fenced JSON block from the reply with `jq`. Extract `charts[]` and `rejected[]`. For each chart:

1. Compute `NN` (zero-padded index 01..05) and `<short>` = `bash "${CLAUDE_PLUGIN_ROOT}/scripts/slugify.sh" "<chart.title>"` (slugify.sh caps at 40 chars — fine).
2. Write the spec JSON to a tempfile via `mktemp`.
3. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/render_chart.sh" "$tempfile" "$report_dir/figures/chart-NN-<short>.png"`. This call both fetches the PNG and writes the adjacent `chart-NN-<short>.meta.json` (which preserves the spec for reproducibility).
4. Delete the tempfile.
5. On success: record `{id, title, png_rel: "figures/chart-NN-<short>.png"}` into `charts_rendered[]` and read `source_ids` from the just-written meta.json.
6. On failure (non-zero exit from render_chart.sh): append `{chart_id, error}` to `failures_charts[]` and continue.

### Stage V4 — Extract diagrams (only with --diagrams)

Dispatch `agents/visualizer-diagrammer.md`. Parse `diagrams[]`. Keep the raw mermaid text in memory for the patch step.

### Stage V5 — Build slide deck (only with --slides)

Dispatch `agents/visualizer-deck.md` with inputs that include the already-rendered `charts_rendered[]` and (if present) `diagrams[]`. Receive the `slides.md` content (inside a fenced `markdown` block). Write it to `$report_dir/slides.md`.

Then run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/render_slides.sh" "$report_dir/slides.md"`. On non-zero exit, record `{error: "marp_failed"}` in `failures_slides[]` but keep going.

### Stage V6 — Build viz block and patch README

Construct a single markdown block combining:

- If `charts_rendered` is non-empty:
  ```
  ## 시각 자료

  ### {{chart.title}}

  ![{{chart.title}}]({{chart.png_rel}})

  > 출처: [{{src_ids joined}}]
  ```
  (one block per chart; `src_ids` from `chart.meta.json`'s `source_ids`)

- If `diagrams` is non-empty (only under `--diagrams`):
  ```
  ## 구조 다이어그램

  ### {{diagram.title}}

  ```mermaid
  {{diagram.mermaid}}
  ```

  > 출처: [{{diagram.evidence_src_ids joined}}]
  ```
  (one per diagram)

Write the combined block to a tempfile, then run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/patch_readme.sh" "$report_dir/README.md" "$tempfile"`.

If both `charts_rendered` and `diagrams` are empty AND there is no existing viz block, skip the patch entirely.

### Stage V7 — Persist viz.json

Write `$report_dir/viz.json`:

```json
{
  "slug": "...",
  "generated_at": "<ISO>",
  "flags": { "slides": true, "diagrams": false, "fresh": false },
  "charts": [ { "id": "c1", "title": "...", "png_rel": "figures/..." } ],
  "diagrams": [ { "id": "d1", "title": "...", "placement": "...", "evidence_src_ids": [1,2] } ],
  "slides": { "md": "slides.md", "pptx": "slides.pptx|null", "pdf": "slides.pdf|null" },
  "rejected_charts": [ ... ],
  "failures": { "charts": [...], "slides": [...] }
}
```

### Stage V8 — Final message

Print a two-line summary:

- Line 1: paths (README.md, any generated `slides.*`, count of figures).
- Line 2: `viz.json` path + failure count (or "no failures").

Do NOT push to Notion automatically. Mention to the user if Mermaid was added: "Run `bash scripts/push_to_notion.sh <report_dir>` to mirror the new diagrams to Notion."

## Idempotency

- If `$report_dir/figures/chart-NN-<short>.png` already exists and `--fresh` is absent, skip both the spec tempfile and the render call for that chart. Still include it in `charts_rendered[]` (read title/source_ids from the existing meta.json).
- README patch replaces the marker block in place.
- `slides.md` is overwritten each run (cheap to regenerate).

## Failure policy

Never abort the whole pipeline because a single chart/diagram/slide failed. Aggregate failures in `viz.json.failures[]` and keep going. Only exit non-zero if Stage V1 (session load) fails.
````

- [ ] **Step 2: Commit**

```bash
git add commands/research-visualize.md
git commit -m "feat(commands): add /research-visualize orchestrator"
```

---

## Task 11: Manual Acceptance Checklist

**Files:**
- Create: `tests/acceptance/research-visualize.md`

- [ ] **Step 1: Write acceptance checklist**

Create `tests/acceptance/research-visualize.md`:

```markdown
# Acceptance: /research-visualize

Pre-req: plugin installed locally, an existing research session under `research/<slug>/` (create one via `/research` if needed).

## 1. Default run (charts only)

- [ ] `/research-visualize <slug>` exits 0.
- [ ] `research/<slug>/figures/` contains ≥ 1 PNG + matching `.meta.json`.
- [ ] Each `.meta.json` has `source_ids` populated.
- [ ] `research/<slug>/README.md` has a new `<!-- viz:begin --> ... <!-- viz:end -->` block with `## 시각 자료` inside.
- [ ] `research/<slug>/viz.json` exists and contains `charts[]`.
- [ ] If extractor found nothing: `viz.json.note == "no_chartable_data"` and README is unchanged (no marker block added).

## 2. Diagrams

- [ ] `/research-visualize <slug> --diagrams` adds `## 구조 다이어그램` inside the marker block.
- [ ] Mermaid blocks render as code blocks in local preview (e.g., VS Code).
- [ ] Each diagram has a `> 출처: [...]` caption.

## 3. Slides

- [ ] `/research-visualize <slug> --slides` produces `slides.md`, and (if `npx` available) `slides.pptx` + `slides.pdf`.
- [ ] Opening `slides.pptx` in Keynote/PowerPoint renders the charts as images on dedicated slides.
- [ ] If `npx` is missing or offline, `slides.md` still exists; `viz.json.failures.slides[]` mentions marp failure; overall command still exits 0.

## 4. Idempotency

- [ ] Re-run `/research-visualize <slug>` — no changes to existing `figures/*.png` (skipped by timestamp).
- [ ] Re-run `/research-visualize <slug>` — README marker block is unchanged (idempotent).

## 5. Fresh

- [ ] `/research-visualize <slug> --fresh` overwrites `figures/`, regenerates PNGs (new `rendered_at`), replaces README block contents.

## 6. Notion mirroring

- [ ] After `--diagrams`, running `bash scripts/push_to_notion.sh research/<slug>` mirrors the Mermaid blocks into the Notion page (visible as rendered Mermaid in Notion).
- [ ] Chart PNG references (`![](figures/...)`) in README are not visible in Notion (expected — v1 limitation; page remains clean, no broken links).

## 7. Session missing

- [ ] `/research-visualize non-existent-slug` exits non-zero with a clear error pointing at the missing directory.
```

- [ ] **Step 2: Commit**

```bash
git add tests/acceptance/research-visualize.md
git commit -m "test(acceptance): add /research-visualize manual checklist"
```

---

## Task 12: Docs Update

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `DEVELOPMENT.md`

- [ ] **Step 1: Update README.md — Usage section**

Locate the `## Usage` section in `README.md`. After the existing `/research-followup` lines, add:

```markdown

/research-visualize <slug>                # generate data charts in README
/research-visualize <slug> --diagrams     # + Mermaid diagrams
/research-visualize <slug> --slides       # + Marp slide deck (.pptx/.pdf)
/research-visualize                        # use most recent session
```

- [ ] **Step 2: Update README.md — Add Visualization section after Notion section**

After the existing `## Notion mirroring (optional one-time setup)` section, insert:

```markdown

## Visualization (optional)

`/research-visualize <slug>` post-processes a completed session into data charts (QuickChart PNG, default), Mermaid diagrams (`--diagrams`), and Marp slide decks (`--slides`). Outputs land under `research/<slug>/figures/` and `research/<slug>/slides.*`. The README gains a `<!-- viz:begin --> ... <!-- viz:end -->` block that's safe to re-run (idempotent).

Mermaid diagrams are mirrored to Notion automatically by `push_to_notion.sh` (they're plain markdown). Chart PNGs are local-only in this version — run `push_to_notion.sh` again after `/research-visualize` to re-sync the Mermaid text.
```

- [ ] **Step 3: Update README.md — Add optional dep**

In the `## Requirements` section, append:

```markdown
- Optional: `npx` (Node 18+) — only when using `/research-visualize --slides` to render via `@marp-team/marp-cli`.
```

- [ ] **Step 4: Update CHANGELOG.md — Add 0.3.0 entry**

Prepend (above `## 0.2.0 — 2026-04-18`):

```markdown
## 0.3.0 — 2026-04-20

### Added
- `/research-visualize <slug>` slash command — generates data charts (QuickChart PNG, default), optional Mermaid diagrams (`--diagrams`), and optional Marp slide decks (`--slides`) for an existing research session.
- `lib/chart_spec_contract.md` — JSON schema for chart specs produced by the extractor subagent and consumed by `render_chart.sh`.
- New subagents: `visualizer-extractor`, `visualizer-diagrammer`, `visualizer-deck`.
- New scripts: `scripts/load_session.sh`, `scripts/render_chart.sh`, `scripts/render_slides.sh`, `scripts/patch_readme.sh`.
- Bats tests: `test_load_session.bats`, `test_patch_readme.bats`, `test_render_chart.bats`.
- `tests/fixtures/sample-session/` fixture for unit tests.
- README viz block is idempotent (marker-bounded) so re-runs don't drift.
- Notion: Mermaid diagrams added by `--diagrams` are mirrored automatically via existing markdown path in `push_to_notion.sh` (no scripts touched).

### Notes
- Chart PNG upload to Notion is deliberately out of scope for 0.3.0 (v2 follow-up).
- `/research` main pipeline and adapter contract are unchanged.
```

- [ ] **Step 5: Update DEVELOPMENT.md**

Under `## Running shell tests`, append:

```markdown

New bats files added in 0.3.0:
- `tests/bats/test_load_session.bats`
- `tests/bats/test_patch_readme.bats`
- `tests/bats/test_render_chart.bats`
```

- [ ] **Step 6: Run full bats suite to confirm nothing regressed**

```bash
bats tests/bats/
```

Expected: all tests pass (existing + new).

- [ ] **Step 7: Commit docs**

```bash
git add README.md CHANGELOG.md DEVELOPMENT.md
git commit -m "docs: document /research-visualize and 0.3.0 release notes"
```

---

## Verification Checklist

Before calling done:

- [ ] `bats tests/bats/` is green (all existing + 3 new files).
- [ ] `scripts/load_session.sh`, `scripts/render_chart.sh`, `scripts/patch_readme.sh`, `scripts/render_slides.sh` are `chmod +x`.
- [ ] `commands/research.md` untouched (no lines changed — verify `git log -p commands/research.md` shows no commits on this branch).
- [ ] `agents/*-adapter.md` untouched.
- [ ] `scripts/push_to_notion.sh` untouched.
- [ ] `lib/adapter_contract.md` untouched.
- [ ] Manual acceptance checklist (`tests/acceptance/research-visualize.md`) passes on at least one real session.
