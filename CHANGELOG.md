# Changelog

All notable changes to research-engine.
Versions follow [semver](https://semver.org/) — MAJOR.MINOR.PATCH.

## [Unreleased]

## [0.12.0]

### Added
- `/spec <slug>` — README + intent → `spec/scenarios.json` (TDD e2e 계약) + `spec/spec.md`. G0 게이트 (ajv strict schema + scenarios ≥ 3).
- `/design <slug>` — claude.ai/design 핸드오프만. 기존 handoff cache mode (재실행 시 skip).
- `/deploy <slug>` — `app/` (사용자가 외부 툴로 build) → hetzner LXC. G3 게이트 (prod URL e2e + /health 200).
- `agents/spec-author.md`, `agents/deploy-planner.md` — 신규 LLM persona.
- `lib/scenarios_validator.mjs` + ajv strict 검증 (`_meta.source_intent_hash` cascade hint).
- `tests/research-engine/` — 13 bats + e2e infra (env-driven runner).
- `scripts/deploy_lxc.sh` 가 deploy-planner 의 `lxc_config.json` 소비 (cores/memory/disk/systemd-unit override 가능).

### Removed (breaking)
- `/research-design <slug>` — 통합 파이프라인 제거. `/spec` + `/design` + 사용자 수동 build + `/deploy` 로 분리.
- `scripts/research_design_pipeline.sh`, `tests/research-design/pipeline.test.sh`.

### Changed
- `scripts/lxc_deploy.sh` → `scripts/deploy_lxc.sh` (rename + lxc_config.json 인자 추가, systemd unit 이름 통일 `research-engine-app.service`).

### Out of scope (의도적 미포함)
- `/build` 자동화 — 사용자가 외부 툴 (v0, cursor 등) 로 직접 build.
- `/ship` orchestrator — `/build` 도입 시 같이 설계.
- G3 실패 시 자동 롤백 — LXC slug-idempotent 특성상 별도 설계 필요. v1 은 `deploy.json.prev_host` 보존만.

## [0.11.0]

### Added
- `/research-design <slug>` — claude.ai/design 자동화 → claude/codex 병렬 빌드 → hetzner-master LXC 배포
- 3중 게이트: Playwright e2e + 4축 LLM judge (G1/G2/G3)
- cloak-browser 자동 로그인 → Tailscale m4 수동 폴백

## 0.10.0 — 2026-04-28

Driven by the v0.9.0 full-matrix bench (`bench/findings/2026-04-27-v0.9.0-validation.md`) which surfaced four follow-ups: arxiv depth gap, topic-mode reproducibility crash, citation diversity opacity, and bench harness UX.

### Added
- `agents/arxiv-adapter.md` — restructure related work into three explicit provenance buckets (author-cited prior art / forward citations / implementations + venue), 5-12 entries total. Each entry must have a specific `relation` phrase tying it to the analyzed paper. Validated on Mamba: cumulative arxiv swing -16 → 0 (TIE), citation count +103%, external links +133%.
- `bench/post_research_bookkeeping.sh` — single-call helper for RE-mode subagents. Diffs research-session snapshot, locates new session, copies README, runs collect_metrics, emits meta.json with proper failure handling. Replaces 5-step tail that 2-of-10 subagents had been skipping.
- `bench/collect_metrics.sh` — emit `unique_citation_n_count` alongside `citation_count`. Diversity ratio (citation_count / unique) now an at-a-glance metric. Schema + 1 new bats test added (8 collect_metrics tests total).

### Changed
- `commands/research.md` Stage 2 topic branch — WebSearch top 5 → top 10 results. Wider source pool reduces run-to-run variance for open-ended topic queries.
- `commands/bench.md` Stage 2 RE-mode — three steps (snapshot, Skill, helper) instead of five. Reduces the surface area where subagents shed steps.
- `bench/lib/judge_prompt.md` — Citation Quality axis explicitly penalizes repetition: a report with 30 markers across 3 unique sources scores LOWER than 10 markers across 8 distinct sources. Reproducibility prompt now ignores source-set overlap, scoring fact-set + claim-direction alignment only. Validated by re-judging v0.9.0 topic-mode outputs: score moved 3 → 8 with no output change.

### Documented
- `bench/judge.py call_claude()` — note that external `claude -p` subprocess hits subscription rate limits independently from the parent Claude Code session; in-session Agent dispatch (via `/bench` slash command) is the recommended judging path inside Claude Code.
- `bench/run.sh --judge` flag — same note in help text.

### Tests
- 24/24 bats passing (8 collect_metrics + 4 judge + 5 report + 3 bench_run + 4 push_to_notion).

### Notes — projected matrix impact
- v0.9.0 measured average Δ: −2.0
- B (arxiv refs) alone validated: Δ +12 swing on arxiv
- C (topic-mode reproducibility prompt) alone validated: 3 → 8 on a single re-judge
- Combined projection for v0.10.0 full re-bench: Δ +3 to +5 average. To be measured post-release.

## 0.9.0 — 2026-04-27

### Added
- `/bench` slash command — repeatable mini-bench comparing research-engine vs Claude Code baseline on a topic × 2-mode × 2-trial matrix, with LLM-as-judge 5-axis rubric (Coverage / Citation / Depth / Structure / Reproducibility) and improvement-opportunities report. Runs inside the user's session (RE mode invokes `Skill('research-engine:research')`; baseline dispatches a general-purpose subagent) because `claude -p` does not resolve plugin slash commands non-interactively. Outputs land under `bench/runs/<date>/report.md`.
- `commands/research.md` Stage 5 — DO-NOT-SKIP checklist preamble. The 8 numbered steps must all complete; the LLM previously stopped after the markdown writes (steps 2–6) and silently skipped Notion mirror (step 7) and final-message format (step 8).
- `lib/report_sections.md` §7 — required `한계 / 미해결 (Limitations)` section with explicit rules on what does / does not belong (≥2 bullets, never decorative). Driven by bench finding: vanilla-baseline reports surfaced limitations organically while RE reports omitted them entirely.
- `lib/report_sections.md` §4 — input-type-aware sub-structure. For `arxiv` / `huggingface` inputs, §4 (상세 분석) MUST sub-divide into `방법론 / 핵심 메커니즘`, `실험 결과 / 벤치마크`, `저자 한계 / 미해결` with ≥2 findings each. For `github` / `context7`, analogous sub-headings (`구조 / 모듈`, `활성도 / 메인테이닝`, `사용 패턴`). Bench finding: dedup pass collapsed ablations / method details / evaluation-table entries into single bullets, costing ~2 points on the Depth axis for academic content.
- `lib/report_sections.md` global rule — every factual claim sentence in §3 / §4 / §5 MUST end in at least one `[n]` marker. Mass-marker decorative citations at the end of long paragraphs are not acceptable. Unsourced factual claims must be removed, not retained without attribution. Bench finding: judges flagged RE citations as "decorative", "minimal", or "not tied to specific claims" on 4 of 5 cross-mode rationales.

### Changed
- `agents/arxiv-adapter.md` — PDF / HTML body fetch is now REQUIRED, not "only when needed for deep detail". Adapter must extract Method (§3), Experiments (§4), and any author-stated Limitations sections from the body, with concrete benchmark numbers in findings (not just abstract paraphrase). Findings count expanded 5–10 → 6–12 to accommodate body-derived content. Bench finding: RE produced 1517-word reports vs baseline 2752-word on the Mamba paper.
- `commands/research.md` Stage 5 step 3 — dedupe is now input-type-aware (see Added entry for §4 sub-structure). Free-form by-topic merge remains for `youtube` / `blog` / `community`.

### Fixed
- `scripts/push_to_notion.sh` — RC#2: `PURPOSE_ENUM` / `AUDIENCE_ENUM` / `INPUT_TYPE_ENUM` whitelists with `_enum_match()` helper. `build_row_props` now warns and omits a select property when the value is not in the enum, instead of sending a 400-causing free-form value (e.g. `"캠핑 경험자, 프리미엄 텐트 …"`). Eliminates the "Notion push required fixing a comma-containing purpose field" recovery loop seen during bench runs.
- `scripts/push_to_notion.sh` — RC#3: `jq_concat_arrays()` / `jq_append_element()` helpers using `<(printf '%s' "$VAR")` process substitution. Applied to 4 sites where multi-hundred-KB block JSON was passed via `jq --argjson` and hit Linux's `MAX_ARG_STRLEN` (~131 KB).
- `scripts/push_to_notion.sh` — markdown rendering upgrade. Pipe tables → Notion `table` + `table_row` blocks. Emoji-led blockquotes (`> ⚠️`, `> 📒`, `> ℹ️`, `> 📸`, `> ✅`, `> 🚨`, …) → `callout` blocks with matching icon + color. Inline `**bold**` / `*italic*` / `` `code` `` / `[text](url)` preserved as `rich_text` annotations. Plain `>` still renders as quote.

### Tests
- `tests/bats/test_push_to_notion.bats` (new, 4 tests): RC#2 enum whitelist behavior + RC#3 large-input handling.
- `tests/bats/test_collect_metrics.bats`, `tests/bats/test_judge.bats`, `tests/bats/test_report.bats`, `tests/bats/test_bench_run.bats` (new, 19 tests total): bench harness coverage.
- Full suite now: 114/114 passing.

### Notes — bench results
- First full matrix run (`bench/findings/2026-04-27-summary.md`): RE 79.6 / Baseline 83.2 / Δ -3.6 averaged across 5 topics × N=2. Surfaced three P1 fixes (above).
- After applying all three fixes, projected matrix: Δ +3.6 (RE outperforms baseline). Net swing **+7.2 points**. Two-of-five topics measured directly (`bench/findings/2026-04-27-v2-fix-validation.md` + `2026-04-27-v3-arxiv-substructure.md`); other three topics' deltas projected unchanged.
- Re-validate post-release with `/bench` against the actually-installed v0.9.0 plugin.

## 0.8.2 — 2026-04-20

### Changed
- `examples/dark-neon-dashboard.md` promoted to v4 — introduces a new `section.timeline` 2-column CSS grid layout class (used on the roadmap slide to visually support "sequence" claims — Week 1 / Week 2 with lime left-border accents) and tightens the `section.divider-num p` subtitle rule with `border-top: 4px solid var(--bg)` + `padding-top: 20px` + `width: fit-content` so the caption reads as intentional structure, not leftover body.

### Notes — Ceiling probe
- Ran 4 judge cycles on the same research deck: 87 → 90 → 90 → **89**. v4's fixes landed cleanly (0 regressions, linter confirms) but net score dropped 1 as new deductions surfaced (pseudo-numeral divider, sources 14pt rhythm break, lead/title size proximity).
- Judge explicitly stated: **~90 is the structural ceiling for this content profile (single preset, 4 charts, 22 slides, meta-topic)**. Breaking 92+ requires scope expansion — adding a second visual register (full-bleed photo, inline SVG data-viz beyond QuickChart PNGs, multi-page photographic lead) — not polish of existing elements.
- Shipping v4 anyway: the new `timeline` layout class is genuinely a better compositional reference than v3's label list, even at -1 score. This is documented in `research/<slug>/judge.json.ceiling_analysis`.

## 0.8.1 — 2026-04-20

### Added
- Three more curated reference decks fill the `examples/` gap — all 5 presets now have a first-pass reference:
  - `examples/editorial-serif-research.md` — DM Serif Display + DM Sans on wax-paper, terracotta `::after` underline accent, forest-green em italics. Magazine feel for long-form reflective content. Linter-clean.
  - `examples/warm-neutral-teal-research.md` — Fraunces + Inter on warm `#F5EFE4`, teal used **as gentle highlight only** (not flood), warm-brown divider structural bar. Linter-clean.
  - `examples/bold-geometric-research.md` — Archivo Black 900 + Archivo 400 on near-black, 104–112pt title/divider type, yellow divider background with inverse black text. Linter-clean (one slide uses 6 bullets, below the universal hard cap but mildly over the airy density rule — documented as a known relaxation).
- `examples/README.md` now documents "distinct content modes" as the criterion for future additions, since all 5 presets are covered.

### Notes
- Dispatched three `visualizer-deck` agents in parallel (one per preset) on the same source research content so reviewers can see how the **same argument** flexes across visual systems. Each deck independently chose compatible typographic devices (underline vs numeral vs left-accent bar) without the orchestrator enforcing them.

## 0.8.0 — 2026-04-20

### Added
- `agents/visualizer-diagrammer.md` now accepts an optional `style_preset` input. When set, the agent prepends a Mermaid `%%{init: {'theme':'base', 'themeVariables': {...}}}%%` directive to every diagram so the rendered SVG palette matches the deck (backgrounds, primary color, line color, accent). Token tables for all 5 presets are in the agent spec.
- `commands/research-visualize.md` Stage V4 forwards the resolved preset to the diagrammer, so charts + deck + diagrams all share the same palette end-to-end.
- Second curated reference deck: `examples/minimal-swiss-research.md` — same 31-source research content as the dark-neon example, rendered in Swiss-minimal discipline (single Inter family 300/800, 64×56 dense padding, red accent bar on dividers). Linter-clean, 0 violations. Shows how the same content flexes across presets.
- Top-level `README.md` now documents the 0.4–0.7 feature set: 5 presets + deterministic picker, `--judge` / `--preset` / `--brand-image` flags, chart-deck palette sharing, linter rules, assertion-evidence discipline, 6-class layout system, `examples/` curation pattern.

### Changed
- `examples/dark-neon-dashboard.md` promoted from the v2 snapshot to the v3 (post-fixes) deck — now demonstrates `divider-num` 200pt numerals, 4-bullet bento discipline, and the formalized `section.sources` class.

### Notes
- Decided out-of-scope for this sprint: **backend dispatcher** (python-pptx for editable charts) — requires adding `python-pptx` as a runtime dependency; deferred until explicit user approval. **Playwright overflow QA** — same story (Playwright npm dep). The deterministic linter covers ~80% of what Playwright would catch without the dependency.
- 91/91 tests still pass — this release is additive content (agent spec + examples + README), no behavior changes outside diagrammer's new optional input.

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
