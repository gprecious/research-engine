---
description: Generate charts, optional Mermaid diagrams, and optional Marp slides for an existing research session.
argument-hint: "[<slug>] [--slides] [--diagrams] [--judge] [--preset <name>] [--brand-image <url>] [--fresh] [--no-sync-notion]"
allowed-tools: Bash, Read, Write, Edit, Agent, Glob, Grep
---

## Inputs

`$ARGUMENTS` — parse:
- positional `slug` (optional; if absent, use the most recent session)
- `--slides` — also generate `slides.md` + `.pptx` + `.pdf`
- `--diagrams` — also generate Mermaid diagrams in the README viz block
- `--judge` — after building slides, score the deck against the 4-axis rubric and, if <75, automatically regenerate once applying the judge's fix-list (requires `--slides`)
- `--preset <name>` — force both charts and deck to use one of the 5 named style presets from `lib/style_presets.md` (`dark-neon` / `editorial-serif` / `minimal-swiss` / `warm-neutral-teal` / `bold-geometric`). Without the flag, charts render on white + Okabe-Ito and the deck agent infers its own preset — which can visually disagree with the charts.
- `--brand-image <url>` — forwarded to `render_chart.sh --brand-image`. Injects QuickChart's `backgroundImageUrl` plugin so every chart is rendered on top of the supplied watermark/brand image. URL must be publicly reachable by QuickChart.
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
3. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/render_chart.sh" [--preset "$preset"] [--brand-image "$brand_image"] "$tempfile" "$report_dir/figures/chart-NN-<short>.png"`. Forward `--preset` when the command flag is set. If `--preset` is absent AND `--slides` is present, run `scripts/pick_preset.py` on `README.md` FIRST (before Stage V3 starts) so the auto-picked preset is forwarded to every chart render — charts and deck then share a single preset end-to-end. Also forward `--brand-image` when set. Render auto-switches to POST /chart when the encoded Chart.js config exceeds ~1900 chars. meta.json preserves the spec, chosen preset, brand image, and render method for reproducibility.
4. Delete the tempfile.
5. On success: record `{id, title, png_rel: "figures/chart-NN-<short>.png"}` into `charts_rendered[]` and read `source_ids` from the just-written meta.json.
6. On failure (non-zero exit from render_chart.sh): append `{chart_id, error}` to `failures_charts[]` and continue.

### Stage V4 — Extract diagrams (only with --diagrams)

Dispatch `agents/visualizer-diagrammer.md` with inputs `{readme, sources, slug, report_dir, style_preset: "<resolved_preset>"}` — the resolved preset from Stage V5 (or, if Stage V5 hasn't resolved it yet, run `pick_preset.py` here as a one-shot) so Mermaid diagrams visually match the deck palette. Parse `diagrams[]`. Keep the raw mermaid text in memory for the patch step.

### Stage V5 — Build slide deck (only with --slides)

Determine the effective style preset:
1. If `--preset <name>` was passed, use that.
2. Otherwise, run `preset=$(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/pick_preset.py" "$report_dir/README.md")` and use its output. The picker is deterministic and grounded in content keywords — this replaces the deck agent's Step-1 inference with a reproducible choice.
3. Record the chosen preset in `viz.json.flags.preset` regardless of source (`--preset` flag, picker, or `null` if the user disabled both, though that path isn't currently exposed).

Dispatch `agents/visualizer-deck.md` with inputs that include the already-rendered `charts_rendered[]`, (if present) `diagrams[]`, and `"style_preset": "<resolved_preset>"`. The deck agent must use that preset verbatim — Step 1 inference is only a fallback when `style_preset` is absent from the inputs. Receive the `slides.md` content (inside a fenced `markdown` block). Write it to `$report_dir/slides.md`.

Then run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/render_slides.sh" "$report_dir/slides.md"`. On non-zero exit, record `{error: "marp_failed"}` in `failures_slides[]` but keep going.

### Stage V5.1 — Lint slides.md (only with --slides)

Immediately after Stage V5 writes `slides.md`, run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/lint_slides.py" "$report_dir/slides.md" "$report_dir/sources.json" > "$report_dir/lint.json"`. Passing `sources.json` as the second arg activates the `source_marker_unresolved` rule — every `[n]` citation in slides.md is verified against the declared sources. The linter exits 0 regardless of findings — it's advisory.

Parse `lint.json`:
- If `violations[]` is non-empty AND `--judge` is also set, include the violations in the judge dispatch prompt so the judge knows the mechanical rule breaks without re-deriving them.
- If `violations[]` is non-empty AND `--judge` is NOT set, log them to stdout as `viz: lint flagged N violation(s) — consider --judge for auto-refine`.
- `warnings[]` (declared exceptions like `section.sources`) are informational only; never escalated.

The linter catches mechanical rule breaks (bullets/words/slide count, body-size, font-family count, noun-phrase headings) BEFORE the expensive judge dispatch — the judge can focus on the subjective axes (Design Quality, Originality) instead.

### Stage V5.5 — Judge (only with --judge, requires --slides)

If `--judge` was passed and Stage V5 wrote a `slides.md`:

1. Dispatch `agents/visualizer-judge.md` as a single Agent call with inputs `{slides_md, pptx_path, pdf_path, readme, charts: charts_rendered, slug, report_title}`. The judge returns a single fenced JSON block per its output schema.
2. Parse with `jq`. Extract `verdict`, `total`, `scores`, `fixes[]`.
3. Persist the verdict as `$report_dir/judge.json`.
4. If `verdict == "FAIL"` AND this is the first judge pass of the run:
   - Dispatch `agents/visualizer-deck.md` a second time with an additional `fixes` field in its input (`{...original_input, fixes: <array from judge>}`). The deck agent must apply every fix — do not cherry-pick.
   - Overwrite `$report_dir/slides.md` with the new content.
   - Re-run `render_slides.sh`.
   - Re-dispatch the judge on the new deck to produce the final `judge.json`. Do NOT loop a third time — two passes is the hard cap (matches the daymade/ppt-creator precedent and prevents infinite grind).
5. On judge dispatch failure (non-JSON reply, dispatch error), record `{error: "judge_failed", detail: "..."}` in `failures_slides[]` but keep the original `slides.md`.

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
  "flags": { "slides": true, "diagrams": false, "judge": false, "preset": "dark-neon|null", "brand_image": "url|null", "fresh": false },
  "charts": [ { "id": "c1", "title": "...", "png_rel": "figures/..." } ],
  "diagrams": [ { "id": "d1", "title": "...", "placement": "...", "evidence_src_ids": [1,2] } ],
  "slides": { "md": "slides.md", "pptx": "slides.pptx|null", "pdf": "slides.pdf|null" },
  "judge": { "verdict": "PASS|FAIL|null", "total": 0, "passes": 0, "file": "judge.json|null" },
  "lint":  { "violations": 0, "warnings": 1, "file": "lint.json|null" },
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

Print a two- to four-line summary:

- Line 1: paths (README.md, any generated `slides.*`, count of figures).
- Line 2: `viz.json` path + failure count (or "no failures").
- Line 3 (when `--judge` was used): `🧑‍⚖️ Judge: <verdict> (<total>/100 after <passes> pass(es))`.
- Line 4 (when pushed): `📒 Notion: <url>` from `sources.json.output_notion_url`.

## Idempotency

- If `$report_dir/figures/chart-NN-<short>.png` already exists and `--fresh` is absent, skip both the spec tempfile and the render call for that chart. Still include it in `charts_rendered[]` (read title/source_ids from the existing meta.json).
- README patch replaces the marker block in place.
- `slides.md` is overwritten each run (cheap to regenerate).

## Failure policy

Never abort the whole pipeline because a single chart/diagram/slide failed. Aggregate failures in `viz.json.failures[]` and keep going. Only exit non-zero if Stage V1 (session load) fails.
