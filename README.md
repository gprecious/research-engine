# research-engine

Deep research via Claude Code slash commands. Give it a URL or a topic — it returns a structured markdown report with citations.

## Installation

From the published marketplace (recommended):

```bash
claude plugin marketplace add gprecious/gprecious-marketplace   # one-time per machine
claude plugin install research-engine@gprecious-marketplace
```

Then restart Claude Code or run `/plugins reload`. Updates via `claude plugin update research-engine@gprecious-marketplace` once a new version is published.

### Local development install (for contributors)

Clone this repo, then register it as a local marketplace:

```bash
git clone https://github.com/gprecious/research-engine
# Point a local marketplace at the repo
mkdir -p research-engine-mp/.claude-plugin
cat > research-engine-mp/.claude-plugin/marketplace.json <<JSON
{
  "\$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "research-engine-local", "version": "0.0.0",
  "owner": { "name": "local-dev" },
  "plugins": [{ "name": "research-engine", "source": "../research-engine", "category": "productivity" }]
}
JSON
claude plugin marketplace add ./research-engine-mp
claude plugin install research-engine@research-engine-local
```

Tip: once installed, replace the snapshot in `~/.claude/plugins/cache/research-engine-local/research-engine/<ver>/` with a symlink to your working copy so local edits reflect without a version bump.

## Usage

```
/research https://youtu.be/xxxxx          # analyze a YouTube video
/research https://arxiv.org/abs/2301.xxxx # analyze a paper
/research "MoE LLM trends in 2026"        # topic research
/research https://... --yes               # skip intent Q&A
/research https://... --fresh             # bypass cache

/research-followup "저자 배경 더"         # ask follow-up on latest session
/research-followup "..." --slug <name>    # target specific session

/research-visualize <slug>                                 # charts + Notion auto-push
/research-visualize <slug> --diagrams                      # + Mermaid diagrams (preset-themed when --preset set)
/research-visualize <slug> --slides                        # + Marp slide deck (.pptx/.pdf)
/research-visualize <slug> --slides --judge                # + 4-axis rubric auto-refine <75 (2-pass cap)
/research-visualize <slug> --slides --preset dark-neon     # force preset (chart + deck + diagram share it)
/research-visualize <slug> --slides --brand-image <url>    # watermark chart background via QuickChart plugin
/research-visualize <slug> --no-sync-notion                # skip Notion push
/research-visualize                                         # use most recent session
```

Output lands in `research/YYYY-MM-DD-<slug>/README.md`. When Notion is configured, a consolidated report is also upserted as a row in a `research-engine` database under the configured parent page (one row per session, re-runs update in place).

## Notion mirroring (optional one-time setup)

When `NOTION_TOKEN` + `NOTION_PARENT_PAGE_ID` are set, every `/research` run upserts a row in a `research-engine` database under the parent page. Each session is a single consolidated page whose body holds the main report plus collapsible toggles for transcript, followups, and related materials. Re-running the same session (e.g. via `/research-followup`) updates the row in place instead of duplicating.

```bash
# 1. Create integration: https://www.notion.so/profile/integrations
#    Grant "Insert content" + "Update content".
# 2. In Notion, share the parent page with the integration (••• → Add connection).
# 3. Save credentials:
mkdir -p ~/.config/research-engine
cat > ~/.config/research-engine/notion.env <<'EOF'
NOTION_TOKEN=secret_XXXX
NOTION_PARENT_PAGE_ID=YOUR_PAGE_ID   # 32-char ID from the shared page URL
EOF
chmod 600 ~/.config/research-engine/notion.env
```

If not configured, `/research` silently skips the Notion step and continues with local markdown only.

## Visualization (optional)

`/research-visualize <slug>` post-processes a completed session into data charts (QuickChart PNG, default), Mermaid diagrams (`--diagrams`), and Marp slide decks (`--slides`). Outputs land under `research/<slug>/figures/` and `research/<slug>/slides.*`. The README gains a `<!-- viz:begin --> ... <!-- viz:end -->` block that's safe to re-run (idempotent).

### Design pipeline (0.4.0+)

Five named style presets live in [`lib/presets.json`](lib/presets.json) — `dark-neon`, `editorial-serif`, `minimal-swiss`, `warm-neutral-teal`, `bold-geometric`. When `--slides` is used, a deterministic [`scripts/pick_preset.py`](scripts/pick_preset.py) chooses one from the README content (override with `--preset <name>`), and that single preset is forwarded to **both** chart rendering (palette/bg/text color) AND the deck agent (Marp `<style>` block + layout classes), so the two stay visually consistent end-to-end.

The deck agent enforces **assertion-evidence headings** ("Q3 revenue grew 23%" — not "Sales Overview"), hard limits (≤70 words/slide, ≤6 bullets/slide, ≤25 slides, body ≥24pt, ≤2 font families), and a 6-class layout system (`title` / `lead` / `divider` / `divider-num` / `bento` / `chart-hero` / `sources`). `scripts/lint_slides.py` runs post-render to catch mechanical violations (including unresolved `[n]` citations against `sources.json`).

`--judge` adds a separate `visualizer-judge` agent that scores the deck 0–100 on Anthropic's 4-axis rubric (Design Quality / Originality / Craft / Functionality, per the [harness-design](https://www.anthropic.com/engineering/harness-design-long-running-apps) post). If <75, the deck agent regenerates with the fix-list (2-pass cap). Scores and fix-lists are persisted to `judge.json` alongside the deck.

`--brand-image <url>` injects QuickChart's [`backgroundImageUrl`](https://quickchart.io/documentation/add-watermark/) plugin so every chart renders over a brand/watermark background. When an encoded Chart.js config exceeds ~1900 chars, `render_chart.sh` auto-switches to POST `/chart` so oversized configs stop failing on GET URL length.

Completed reference decks are curated under [`examples/`](examples/) — the deck agent reads one matching example at the start of every generation (progressive-disclosure pattern). Contribute via `/research-visualize --slides --judge --preset <name>` on a real session and promoting the result if judge ≥90.

### Notion sync

When Notion is configured, the final stage auto-pushes the patched README back to Notion. Chart PNGs are mirrored as Notion image blocks backed by their QuickChart URLs (the URL is stored in each chart's `.meta.json` and reused, so no file upload is needed). Mermaid blocks render natively. `slides.pptx` and `slides.pdf` (when produced via `--slides`) are uploaded to Notion and embedded as file blocks under a "📎 슬라이드 덱" heading. Pass `--no-sync-notion` to skip.

## Requirements

- `yt-dlp` in `PATH` (YouTube captions)
- `gh` CLI authenticated (GitHub)
- `jq` (JSON munging)
- `perl` with UTF-8 support (for Unicode-aware slugify; standard on Debian/Ubuntu)
- Claude Code plugins: `firecrawl`, `context7`, `huggingface-skills`
- Optional: `npx` (Node 18+) — only when using `/research-visualize --slides` to render via `@marp-team/marp-cli`.

## Docs

- User guide: this file
- Design spec: `docs/superpowers/specs/2026-04-16-research-engine-design.md`
- Implementation plan: `docs/superpowers/plans/2026-04-16-research-engine.md`
- Contributor guide: `DEVELOPMENT.md`

## Known limitations

- SNS(X, LinkedIn) 분석은 지원하지 않습니다.
- 페이월이 있는 블로그는 `status: failed` 로 기록됩니다.
- 라이브 스트리밍 / 미확정 자막 영상은 자막 확정 후만 지원.
- `/research-followup` 은 slug 자동 추적 시 가장 최근 mtime 세션을 선택. 여러 세션을 번갈아 쓴다면 `--slug` 를 명시.
- YouTube `yt_fetch.sh metadata` 의 `caption_langs_available` 는 YT 자동 번역 조합을 모두 포함해 수백~수천 항목이 됩니다. `selected_caption_lang` 선택 로직은 영향 없습니다.
