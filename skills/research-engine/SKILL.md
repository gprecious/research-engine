---
name: research-engine
description: Use when the user asks Codex to research a URL, paper, repo, video, blog, documentation page, or topic and produce a structured cited markdown report or follow up on a previous research session using the research-engine workflow.
---

# Research Engine

Use this skill to run the research-engine workflow in Codex. The Claude Code slash commands in `commands/` are the canonical source for the full pipeline; this skill adapts the same contract to Codex tools.

## Outputs

Create or update a session under:

```text
research/YYYY-MM-DD-<slug>/
├── README.md
├── sources.json
├── intent.json
├── session.md          # follow-ups only
├── transcript.md       # YouTube only, when available
└── related/*.md        # when related sources exist
```

Use Korean for synthesized findings and answers unless the user asks for another language. Keep direct quotes in the original language.

## New Research Workflow

1. Parse the request into `target`, optional `--yes`, optional `--fresh`, and optional `--slug <name>`.
2. Classify the target with `scripts/classify_url.sh`.
3. Preview the target:
   - YouTube: verify `yt-dlp`; fetch metadata and captions with `scripts/yt_fetch.sh`.
   - arXiv: fetch title, abstract, and body. Prefer `https://arxiv.org/html/<id>`; fall back to PDF.
   - GitHub: use `gh repo view` when authenticated; otherwise fetch public repo metadata and README from the web.
   - Blog/docs/community URL: fetch the page as markdown or readable text.
   - Topic: perform web search and keep a source pool broad enough for cross-checking.
4. Resolve intent. With `--yes`, infer `{purpose, focus, audience_level, notes}` and mark `intent_mode: "assumed"`. Without `--yes`, ask 1-3 concise questions before continuing.
5. Create `research/YYYY-MM-DD-<slug>/`, save `intent.json`, and gather evidence.
6. Use the adapter contract in `lib/adapter_contract.md` as the internal evidence shape. When a task is broad enough and the user permits parallel agents, dispatch focused subagents matching `agents/*-adapter.md`; otherwise do the same evidence gathering directly with Codex tools.
7. Synthesize `README.md` with the section contract in `lib/report_sections.md`. Every factual claim in `핵심 포인트`, `상세 분석`, and `인용 / 원문` must have a precise `[n]` citation.
8. Write `sources.json` with one-indexed sources, original input, input type, intent, and creation timestamp.
9. If Notion credentials are configured, run `scripts/push_to_notion.sh <report_dir>`, store `output_notion_url` in `sources.json`, and add the Notion line to `README.md`. If not configured, skip silently.
10. Final response: report path plus a two-line TL;DR.

## Follow-Up Workflow

1. Resolve the session from `--slug <name>` or `scripts/find_latest_session.sh research`.
2. Read the session `README.md`, `sources.json`, `intent.json`, and existing `session.md`.
3. Decide whether the question is answerable from existing sources or needs 1-2 new focused fetches.
4. Answer in Korean with existing `[n]` citations; append new sources to `sources.json` only when newly fetched evidence is used.
5. Append the exchange to `session.md` using the format in `commands/research-followup.md`.
6. Push to Notion if configured and report the `session.md` path.

## Quality Bar

- Prefer primary sources over summaries whenever available.
- Do not pad related sources; include only sources with a specific relationship to the target.
- Remove unsupported claims instead of leaving uncited statements.
- For academic inputs, separate method, experiments, and author-stated limitations as described in `lib/report_sections.md`.
- Record partial failures in the report instead of aborting the whole run.
- Before claiming completion, verify that `README.md`, `sources.json`, and `intent.json` exist and citations in `README.md` correspond to entries in `sources.json`.
