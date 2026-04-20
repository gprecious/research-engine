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
