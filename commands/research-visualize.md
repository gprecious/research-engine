---
description: Generate charts, optional Mermaid diagrams, and optional Marp slides for an existing research session.
argument-hint: "[<slug>] [--slides] [--diagrams] [--fresh] [--no-sync-notion]"
allowed-tools: Bash, Read, Write, Edit, Agent, Glob, Grep
---

## Inputs

`$ARGUMENTS` — parse:
- positional `slug` (optional; if absent, use the most recent session)
- `--slides` — also generate `slides.md` + `.pptx` + `.pdf`
- `--diagrams` — also generate Mermaid diagrams in the README viz block
- `--fresh` — wipe and regenerate `figures/`, `slides.*`, and replace the README viz block
- `--no-sync-notion` — skip the auto-push to Notion at the end of the pipeline

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

### Stage V8 — Sync to Notion (default on)

Unless `--no-sync-notion` was passed:

- If `NOTION_TOKEN` and `NOTION_PARENT_PAGE_ID` are set (env or `~/.config/research-engine/notion.env`), run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/push_to_notion.sh" "$report_dir"`. This re-syncs the Notion row's body with the now-patched `README.md` (Mermaid blocks rendered natively; chart `![](figures/...)` references are ignored by the existing `md_to_blocks` parser, so the Notion page stays clean).
- If the env vars are missing, log one line (`viz: Notion env not configured — skipping push`) and continue.
- On push failure, record `{error: "notion_push_failed"}` in `viz.json.failures[]` but do not abort — the local artifacts are authoritative.

### Stage V9 — Final message

Print a two- or three-line summary:

- Line 1: paths (README.md, any generated `slides.*`, count of figures).
- Line 2: `viz.json` path + failure count (or "no failures").
- Line 3 (when pushed): `📒 Notion: <url>` from `sources.json.output_notion_url`.

## Idempotency

- If `$report_dir/figures/chart-NN-<short>.png` already exists and `--fresh` is absent, skip both the spec tempfile and the render call for that chart. Still include it in `charts_rendered[]` (read title/source_ids from the existing meta.json).
- README patch replaces the marker block in place.
- `slides.md` is overwritten each run (cheap to regenerate).

## Failure policy

Never abort the whole pipeline because a single chart/diagram/slide failed. Aggregate failures in `viz.json.failures[]` and keep going. Only exit non-zero if Stage V1 (session load) fails.
