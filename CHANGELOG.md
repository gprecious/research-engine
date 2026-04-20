# Changelog

All notable changes to research-engine.
Versions follow [semver](https://semver.org/) — MAJOR.MINOR.PATCH.

## 0.7.1 — 2026-04-20

### Added
- Two new deterministic rules in `scripts/lint_slides.py`:
  - `heading_duplicated` — same h2 appears on 2+ content slides. Divider / divider-num / sources / title / lead classes are exempt (terse repetition is intentional there).
  - `bg_fit_outside_chart_hero` — Marp's `![bg fit]` page-background directive bypasses the `section.chart-hero img { width: 100% }` CSS rule, so using it outside a `chart-hero` slide creates inconsistent image sizing (judge flagged this in run 1).
- 4 new bats tests covering both rules (positive + negative cases). Full suite 91/91.

### Notes
- Both rules are enforcement layers for structural consistency — the judge can now focus on subjective axes because these mechanical drift patterns are caught pre-dispatch.

## 0.7.0 — 2026-04-20

### Added
- `scripts/pick_preset.py` — deterministic preset selector. Reads README.md, counts keyword hits across 5 preset profiles (dark-neon / editorial-serif / minimal-swiss / warm-neutral-teal / bold-geometric), prints the highest-scoring preset name. Pure stdlib, exits 0 always. Use `--scores` to get per-preset scores as JSON.
- `/research-visualize` now runs `pick_preset.py` automatically when `--preset <name>` is absent and `--slides` is present. Charts and deck share the auto-picked preset end-to-end, removing the previous non-determinism where the deck agent inferred a preset in its own Step 1.
- 12 new bats tests in `tests/bats/test_pick_preset.bats`: every preset picked on representative content, empty-content default, tie-break behavior, frontmatter-ignored, markdown-link label not mis-scored, missing-file error. Full suite 87/87.

### Notes
- `bold-geometric` keywords are deliberately narrow (`launch`, `keynote`, `unveil`, `debut`, `rollout`, `campaign`) so any document that merely mentions "presentation" does NOT flood it. Similarly `product` is excluded — too generic.
- Tie-break order favors `minimal-swiss` (declared default for typography-first reports) → `editorial-serif` → `dark-neon` → `warm-neutral-teal` → `bold-geometric`.
- Frontmatter is stripped before scoring so meta-fields in `---` blocks can't bias the winner.

## 0.6.1 — 2026-04-20

### Added
- `scripts/lint_slides.py` now accepts an optional 2nd arg `<sources.json>`. When provided, every `[n]` citation marker in slides.md is resolved against the declared sources — unresolved markers become `source_marker_unresolved` violations. Catches the exact regression `visualizer-judge` flagged on the v2 deck (13 missing entries).
- `/research-visualize` Stage V5.1 now forwards `$report_dir/sources.json` to the linter so marker resolution runs automatically on every deck render.
- 5 new bats tests for the rule: clean resolution, unresolved marker, grouped `[1,2,3]` markers, markdown-link `[label](url)` NOT misidentified as a marker, malformed sources.json degrades to warning.

### Notes
- Marker detection requires a preceding whitespace/punctuation boundary so markdown links like `[robonuggets/marp-slides](https://...)` never match. Only numeric tokens or comma-lists inside `[...]` trigger the rule.
- Linter now reports `stats.source_markers_referenced` — the sorted list of unique ids actually cited in the deck.

## 0.6.0 — 2026-04-20

### Added
- `scripts/lint_slides.py` — deterministic pre-judge linter for `slides.md`. Catches mechanical rule violations (≤70 words/slide, ≤6 bullets/slide, ≤25 slides total, body ≥24pt, ≤2 font families, assertion-evidence headings) before paying for a `visualizer-judge` dispatch. Python stdlib only, no dependencies. Exits 0 and emits JSON so callers choose severity.
- `/research-visualize` Stage V5.1 runs the linter automatically after `slides.md` is written. `viz.json.lint` now records violation/warning counts and the `lint.json` sidecar path.
- Linter feeds its `violations[]` into the judge prompt when both `--slides` and `--judge` are set, so the judge concentrates on subjective axes (Design Quality, Originality) rather than re-checking mechanical rules.
- 12 new bats tests in `tests/bats/test_lint_slides.bats` covering every rule (bullets, words, slide count, body size, font families, assertion Korean/English heuristics, `section.sources` declared exception, missing file). Full suite now 70/70.

### Notes
- The linter recognizes `section.sources` as a declared exception — its 14pt body and long reference list emit a `warnings[]` entry but never a `violations[]` entry.
- Assertion-heading heuristic: Korean verb-ending detection (다/한다/된다/이다/있다/…) + English common-verb tokens (is/are/has/have/grew/dropped/…). Imperfect but catches the dominant "Sales Overview" failure mode.

## 0.5.1 — 2026-04-20

### Changed
- `lib/presets.json` is now the single source of truth for the 5 preset tokens (palette/bg/text/grid/fonts/density). `scripts/render_chart.sh` loads it at runtime instead of maintaining a hardcoded Python dict. `lib/style_presets.md` explicitly defers to the JSON.
- `lib/style_presets.md` adds `section.sources` as a first-class layout class. The class deliberately violates the 24pt body minimum (drops to 14pt in a 2-column `<ol>`) so 25–35 reference entries fit one slide — this was previously an ad-hoc workaround flagged by `visualizer-judge`. Reports with >35 sources should split into Sources-1/Sources-2 rather than shrinking further.

### Notes
- Consumers can override the preset path via `RESEARCH_ENGINE_PRESETS=<path/to/presets.json>` (useful for testing custom preset sets).
- No test changes — 58/58 still green. The refactor is behavior-preserving.

## 0.5.0 — 2026-04-20

### Added
- `scripts/render_chart.sh --brand-image <url>` — injects QuickChart's `backgroundImageUrl` plugin so every chart renders over a watermark/brand background. Forwarded by the `/research-visualize --brand-image <url>` flag so whole decks can be brand-stamped in one pass.
- QuickChart **POST /chart** auto-switch — when the encoded Chart.js config exceeds ~1900 chars (GET URL length limit), the script now falls back to POST with a JSON body instead of failing with URL-too-long. Small configs keep the GET path so `meta.json.quickchart_url` remains embeddable in Notion.
- `chart.meta.json` gains `render_method` (`"GET"` or `"POST"`) and `brand_image` fields. For POST renders, `quickchart_url` is `null` — the Notion push code already skips image blocks when the URL is missing, so the locally-rendered PNG stays authoritative.
- Three new bats tests in `tests/bats/test_render_chart.bats` covering `--brand-image` injection, the GET path for small configs, and the POST auto-switch for oversized configs (58/58 overall).

### Notes
- `/research-visualize --preset` + `--brand-image` can now produce an in-brand deck without any per-chart manual work. For example: `/research-visualize <slug> --slides --preset dark-neon --brand-image https://example.com/brand-mark-dark.png`.

## 0.4.0 — 2026-04-20

### Added
- `lib/style_presets.md` — 5 named visual presets (`dark-neon`, `editorial-serif`, `minimal-swiss`, `warm-neutral-teal`, `bold-geometric`), each with a 5-color palette, a 2-family font pair, density rules, and a reusable Marp `<style>` template with `bento` / `lead` / `divider` / `chart-hero` layout classes.
- `agents/visualizer-judge.md` — new subagent that scores a rendered deck on 4 axes (Design Quality / Originality / Craft / Functionality, 0–100 total) per Anthropic's harness-design rubric. Separate from `visualizer-deck` to avoid self-evaluation bias.
- `/research-visualize --judge` flag — when combined with `--slides`, automatically scores the deck and, if <75, regenerates once with the judge's fix-list (hard cap of 2 passes).
- `/research-visualize --preset <name>` flag — forces both charts and deck to use the same named preset (one of the 5 from `lib/style_presets.md`), eliminating chart-vs-deck palette mismatch. Forwards to `render_chart.sh --preset <name>` and to the deck agent as a `style_preset` input override.
- `scripts/render_chart.sh --preset <name>` — chart background, text color, grid color, and dataset palette now align with the named preset. Hardcoded tokens kept in sync with `lib/style_presets.md`. Without `--preset`, falls back to the legacy Okabe-Ito palette on white (backwards compatible).
- Four new bats tests in `tests/bats/test_render_chart.bats` covering `--preset` behavior (valid preset sets bg + accent, unknown preset errors, no preset keeps white).
- `examples/` — curated reference decks that `visualizer-deck` Step 0 now reads before generating, to absorb compositional rhythm (progressive-disclosure pattern borrowed from robonuggets/marp-slides). First entry: `examples/dark-neon-dashboard.md` (judge-validated at 90/100).

### Changed
- `agents/visualizer-deck.md` rewritten. Now **requires** picking exactly one style preset from `lib/style_presets.md` and enforces assertion-evidence headings (noun-phrase titles like "Sales Overview" must be rewritten as full sentences with a verb). Hard limits: ≤70 words/slide, ≤6 bullets/slide, ≤2 font families, body ≥24pt, title ≥80pt, ≤25 slides. Every chart slide carries an interpretive assertion above the image; every §상세 분석 slide carries an `[n]` source marker. New optional inputs: `style_preset` (skip inference, use verbatim) and `fixes[]` (apply judge fix-list verbatim on regeneration).
- `viz.json` schema: new `judge` block `{verdict, total, passes, file, style_preset_detected}`; new `flags.judge` and `flags.preset` fields.
- `chart.meta.json` sidecar now records the `preset` used during render (null when legacy).

### Notes
- Existing sessions without `--judge` see no behavior change beyond the stricter deck template.
- The 4-axis rubric maps directly to Anthropic's Claude Design evaluator published in the 2026-03-24 "Harness Design for Long-Running Application Development" post; weights (35/35/15/15) are applied as tie-breakers, totals are simple sums.
- Source research for this bump: `research/2026-04-20-ppt-design-improvement-research/README.md`.

## 0.3.0 — 2026-04-20

### Added
- `/research-visualize <slug>` slash command — generates data charts (QuickChart PNG, default), optional Mermaid diagrams (`--diagrams`), and optional Marp slide decks (`--slides`) for an existing research session.
- `lib/chart_spec_contract.md` — JSON schema for chart specs produced by the extractor subagent and consumed by `render_chart.sh`.
- New subagents: `visualizer-extractor`, `visualizer-diagrammer`, `visualizer-deck`.
- New scripts: `scripts/load_session.sh`, `scripts/render_chart.sh`, `scripts/render_slides.sh`, `scripts/patch_readme.sh`.
- Bats tests: `test_load_session.bats`, `test_patch_readme.bats`, `test_render_chart.bats`.
- `tests/fixtures/sample-session/` fixture for unit tests.
- README viz block is idempotent (marker-bounded) so re-runs don't drift.
- Notion: `/research-visualize` now auto-pushes the patched README to Notion by default. Pass `--no-sync-notion` to opt out.
- Notion: chart PNGs referenced as `![](figures/chart-NN-*.png)` are mirrored as Notion `image` blocks backed by the QuickChart URL stored in each chart's `.meta.json` — no file upload, no external host needed. Mermaid blocks continue to render natively.
- Notion: `slides.pptx` and `slides.pdf` produced by `--slides` are uploaded to Notion via the `file_uploads` API and embedded under a "📎 슬라이드 덱" heading (single-part, up to 20MB each; larger files are skipped with a warning).
- `scripts/push_to_notion.sh`: `md_to_blocks` parser extended with `NOTION_MD_BASE_DIR`-aware image resolution; new `notion_upload_file` helper wraps the two-step create-and-send file upload flow.
- Chart color palette: `scripts/render_chart.sh` now applies an Okabe-Ito qualitative palette — distinct colors per dataset (bar/line/scatter/horizontal_bar) and per slice (pie). Bars/lines are no longer grey-on-grey.

### Notes
- `/research` main pipeline and adapter contract are unchanged.

## 0.2.0 — 2026-04-18

### Changed
- **Notion layout is now a single database with one consolidated row per session** (breaking vs 0.1.0's page tree). Each row's body holds the main report, with toggle blocks for transcript, followups, and related materials.
- `/research-followup` updates the row in place (clear-and-reappend) rather than creating subpages.

### Added
- `scripts/push_to_notion.sh --archive-page <page_id>` subcommand for one-off cleanup.
- Database properties: Title, Slug, Input URL, Input Type, Created, Purpose, Audience, Sources — enabling filter/sort in Notion.
- `NOTION_DATABASE_ID` cache env variable to skip the database search on every run.

### Fixed
- `md_to_blocks` parser used a heredoc that hijacked stdin — the markdown never reached Python. Script now stores the Python source in a bash variable and runs via `python3 -c`, leaving stdin available.

### Removed
- `install.sh` — superseded by marketplace-based installation documented in the README.

## 0.1.0 — 2026-04-17

Initial release. Plugin scaffolding, seven source adapters (YouTube, arXiv, GitHub, blog, context7, HuggingFace, community), `/research` + `/research-followup` slash commands, bash utilities with bats coverage, and Notion mirroring (page-tree layout).
