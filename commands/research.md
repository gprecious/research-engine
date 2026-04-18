---
description: Deep research on a URL (YouTube/arXiv/GitHub/blog/docs) or topic keyword. Produces research/YYYY-MM-DD-<slug>/README.md.
argument-hint: "<URL or topic> [--yes] [--fresh] [--slug <name>]"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, WebFetch, WebSearch
---

## Inputs

`$ARGUMENTS` — raw argument string. Parse into:
- `target` (positional, required): URL or topic text
- `--yes`: skip Intent Q&A, engine infers
- `--fresh`: bypass cache
- `--slug <name>`: manual slug override

## Constants

- `${CLAUDE_PLUGIN_ROOT}` = plugin root, exported by Claude Code into each Bash tool invocation for commands owned by this plugin.
- `RESEARCH_DIR` = `<project_cwd>/research`
- Date today: !`date -u +%Y-%m-%d`

## Pipeline

Execute these stages **in order**. Do not skip stages.

### Stage 1 — Classify

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/classify_url.sh" "<target>"`. Store the result as `input_type`.

### Stage 2 — Preview

Branch by `input_type`:

- **youtube** → Pre-flight: `command -v yt-dlp >/dev/null || { echo "yt-dlp not installed. Install with: pipx install yt-dlp  (or)  brew install yt-dlp" >&2; exit 1; }`. Then `bash "${CLAUDE_PLUGIN_ROOT}/scripts/yt_fetch.sh" metadata "<target>"` → parse title/description/chapters/selected_caption_lang. Extract roughly the first 5 minutes of the selected-lang captions by running `yt_fetch.sh captions` into a temporary dir (or reading cached VTT if it exists).
- **arxiv** → invoke the `huggingface-skills:hugging-face-paper-pages` skill with the arXiv id to get title+abstract.
- **github** → `gh repo view <owner>/<repo> --json ...` + first 2 KB of README.
- **huggingface** → `hf` CLI card summary.
- **blog / community** → invoke the `firecrawl:firecrawl-scrape` skill (or `firecrawl:firecrawl` for more complex crawls) on the URL; take first 2 KB of markdown.
- **topic** → `WebSearch` with `<target>` and keep the top 5 result titles + snippets.

Write the preview to `RESEARCH_DIR/<tmp-slug>/cache/preview-<cache_key>.json` (create dir if needed). Compute `cache_key` via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cache_key.sh" "<target>"`.

### Stage 3 — Intent Q&A

Compute `slug`:
- If `--slug` provided, use it.
- Otherwise run `slugify.sh` on the preview title (or on `<target>` for topic mode).
- Prefix with today's date: `${DATE}-${SLUG}`. Handle collision by appending `-2`, `-3`.

Finalize the report directory `<report_dir> = RESEARCH_DIR/<date>-<slug>/`. If a tmp-slug dir was created in Stage 2, move its contents in.

Then:

- If `--yes` was set, SKIP interactive Q&A. Derive an `intent` object from the preview (your best judgment). Record `intent_mode: "assumed"` in the report frontmatter.
- Otherwise, generate **1–3 dynamic questions** grounded in the preview content and ASK THEM in the chat. Wait for the user's reply. Structure their reply into `intent = { purpose, focus, audience_level, notes }`. Record `intent_mode: "user"`.
- If preview failed, fall back to the 3 fixed questions in `lib/intent_questions_fallback.md`.

Save intent to `<report_dir>/intent.json`.

**실행 모델**: `/research` 슬래시 커맨드는 Intent Q&A 응답을 받을 때까지 블로킹. 사용자는 터미널에서 응답을 타이핑하고, 그 뒤 Stage 4로 진행.

### Stage 4 — Plan & Parallel Dispatch

Apply `superpowers:dispatching-parallel-agents`. Build a work plan:

- **Primary adapter** for the `input_type` (youtube → youtube-adapter, arxiv → arxiv-adapter, etc.). Topic mode has NO primary; it fans out to all tier-1 adapters.
- **Secondary adapters** driven by the preview:
  - If preview mentions arXiv IDs → arxiv-adapter
  - If preview mentions repo URLs → github-adapter
  - If preview mentions library names → context7-adapter (libraries list in the prompt)
  - If preview mentions HF assets → huggingface-adapter
  - If preview links HN/Reddit threads → community-adapter (pass `thread_urls`)
  - For topic mode → all tier-1 + community-adapter with `topic_query`.

Dispatch each adapter with a single Agent call, parallel (issue all Agent tool calls in one assistant message). Per-adapter prompt template:

```
You are dispatched as the <adapter-name> subagent for research session <slug>.

Inputs:
  <JSON of {url|targets|libraries|thread_urls, intent, cache_dir, slug, fresh}>

Return a single fenced JSON block per lib/adapter_contract.md. Do not include anything after the JSON block.
```

Timeout per adapter: 5 minutes (configured implicitly by the agent runtime; do NOT actively retry beyond the single dispatch). If an adapter returns non-JSON or malformed JSON, record it as a failure and continue.

### Stage 5 — Synthesize & Persist

1. Collect adapter outputs. Re-number source ids across adapters into a single one-indexed list `[1]…[N]`.
2. Write `<report_dir>/sources.json` as:
   ```json
   {
     "sources": [
       { "n": 1, "adapter": "...", "type": "...", "url": "...", "title": "...",
         "meta": {...}, "fetched_at": "<ISO>" },
       ...
     ],
     "intent": { ... },
     "input": "<target>",
     "input_type": "<type>",
     "created": "<ISO>"
   }
   ```
3. Write `<report_dir>/README.md` using the templates in `lib/report_sections.md`. Merge findings by topic, not by adapter. Dedupe near-duplicate findings. Preserve `[n]` markers.
4. YouTube only: write `<report_dir>/transcript.md` from the youtube-adapter `artifacts.transcript_md`.
5. For each unique `related[]` entry, write `<report_dir>/related/<kind>-<slug>.md` with a one-paragraph summary + URL. Deduplicate by URL.
6. If any adapter had non-empty `failures[]`, include the `## 수집 실패 (Failures)` section in README.md.
7. **Push to Notion (mirror)** — if `NOTION_TOKEN` + `NOTION_PARENT_PAGE_ID` are set (env or `~/.config/research-engine/notion.env`), run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/push_to_notion.sh" "<report_dir>"`. The script creates or updates a page tree at `<parent>/research-engine/<slug>/` mirroring `README.md`, `transcript.md`, `session.md`, and `related/*.md` as subpages. Capture the returned Notion URL and add it to `sources.json` at `output_notion_url`. Prepend a `> 📒 Notion: <url>` line under the frontmatter of local `README.md`. If the env is not configured, skip silently (log one line).
8. Final message to user: one line with `<report_dir>/README.md` path + Notion URL (if pushed) + a 2-line TL;DR preview.

## Cache policy

- Preview JSON is written under `<report_dir>/cache/preview-<cache_key>.json`.
- Each adapter receives `cache_dir = <report_dir>/cache/` in its inputs. Adapters MAY write `adapter-<name>-<cache_key>.json` for reuse.
- `--fresh` → ignore all cache for this run but still write fresh cache files.

## Failure policy

- Never abort the pipeline because a single adapter failed.
- If ALL adapters fail, still produce a skeleton report with preview content and a prominent Failures section.
- Missing `yt-dlp` on a youtube input → stop before Stage 2 with a clear error telling the user how to install.
