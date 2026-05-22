# research-engine

Deep research via Claude Code slash commands or the Codex skill. Give it a URL or a topic — it returns a structured markdown report with citations.

## Installation

From the published marketplace (recommended):

```bash
claude plugin marketplace add gprecious/gprecious-marketplace   # one-time per machine
claude plugin install research-engine@gprecious-marketplace
```

Then restart Claude Code or run `/plugins reload`. Updates via `claude plugin update research-engine@gprecious-marketplace` once a new version is published.

### Codex plugin install

This repository also contains a Codex-compatible plugin manifest and skill:

```text
.codex-plugin/plugin.json
skills/research-engine/SKILL.md
```

Install it the same way you install local Codex plugins in your environment, pointing the plugin source at this repository. After the plugin is available, ask Codex for research directly, for example:

```text
Use research-engine to research https://arxiv.org/abs/2402.10171 --yes
Use research-engine to research "MoE LLM routing improvements" --yes
Use research-engine to follow up on the latest session: "저자 한계만 더 정리해줘"
```

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

### Claude Code slash commands

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

/research-design <slug>                                    # research → claude.ai/design → LXC 배포
/research-design <slug> --no-deploy                        # 로컬 산출물까지만
/research-design <slug> --login-headful                    # cloak skip, Tailscale m4 로 1회 로그인
/research-design <slug> --fresh                            # storageState 캐시 무시
```

Output lands in `research/YYYY-MM-DD-<slug>/README.md`. When Notion is configured, a consolidated report is also upserted as a row in a `research-engine` database under the configured parent page (one row per session, re-runs update in place).

### AI agent instructions

Agents that cannot execute Claude Code slash commands should use `skills/research-engine/SKILL.md` as the entrypoint and treat the command files as the canonical pipeline reference:

- `commands/research.md` defines the full classify → preview → intent → evidence → synthesize → persist workflow.
- `commands/research-followup.md` defines session follow-ups.
- `lib/adapter_contract.md` defines the normalized evidence JSON shape.
- `lib/report_sections.md` defines the required markdown report sections and citation rules.
- `agents/*-adapter.md` defines source-specific collection behavior.

For a new research run, create `research/YYYY-MM-DD-<slug>/README.md`, `sources.json`, and `intent.json`. Use the same report structure as `lib/report_sections.md`; every factual claim in `핵심 포인트`, `상세 분석`, and `인용 / 원문` must cite a real source id such as `[1]`.

For Codex specifically:

1. Use the `research-engine` skill when the request asks for URL, paper, repo, video, blog, docs, community, or topic research.
2. Use Codex web/search/file tools in place of Claude `WebSearch`, `WebFetch`, `Read`, `Write`, and `Edit`.
3. Use Codex subagents only when the user explicitly allows delegation or parallel agents; otherwise collect the adapter evidence directly.
4. Use shell scripts in `scripts/` for deterministic helper behavior such as URL classification, slugging, cache keys, YouTube metadata, latest-session lookup, and Notion mirroring.
5. Preserve the output contract: cited Korean markdown report, machine-readable `sources.json`, saved `intent.json`, optional `transcript.md`, optional `related/`, and append-only `session.md` for follow-ups.
6. Before reporting success, verify the artifacts exist and that cited `[n]` markers map to `sources.json`.

### Bench mode

`/bench` runs a self-comparison harness: research-engine vs vanilla Claude Code (general-purpose subagent) on the same topic set, scored by LLM-as-judge on 5 axes (Coverage / Citation / Depth / Structure / Reproducibility). Outputs land in `bench/runs/<date>/report.md` with an `Improvement opportunities` section.

The matrix runs **inside the user's Claude Code session** (not as `claude -p` subprocesses) because plugin slash commands do not resolve in non-interactive `claude -p` mode. RE mode invokes `Skill('research-engine:research', ...)`; baseline mode dispatches a general-purpose subagent with the topic's `baseline_prompt`. See `commands/bench.md` for the full pipeline.

```
/bench --check                          # preflight only
/bench --topic smoke --no-judge         # 1–2 min plumbing smoke
/bench                                  # full matrix (~3 hours)
/bench --topic <id> --force             # re-run a single topic
/bench --report-only                    # regenerate report from existing results.json
```

Spec: `docs/superpowers/specs/2026-04-26-research-engine-bench-design.md`.

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

### Optional: `/research-design` deps

- Node 22 + pnpm 9, `pnpm install`
- Playwright chromium: `pnpm exec playwright install chromium --with-deps`
- cloak-browser (lazy install)
- `.env.research-design` (`.env.research-design.example` 참조)
- herdr session (`HERDR_ENV=1`), Tailscale, hetzner-master ssh
- 새 슬러그 추가 시: `research/<slug>/design/scenarios.json` 은 `git add -f` 필요 (`.gitignore` 의 blanket `research/` 때문)

## Known limitations

- SNS(X, LinkedIn) 분석은 지원하지 않습니다.
- 페이월이 있는 블로그는 `status: failed` 로 기록됩니다.
- 라이브 스트리밍 / 미확정 자막 영상은 자막 확정 후만 지원.
- `/research-followup` 은 slug 자동 추적 시 가장 최근 mtime 세션을 선택. 여러 세션을 번갈아 쓴다면 `--slug` 를 명시.
- YouTube `yt_fetch.sh metadata` 의 `caption_langs_available` 는 YT 자동 번역 조합을 모두 포함해 수백~수천 항목이 됩니다. `selected_caption_lang` 선택 로직은 영향 없습니다.
