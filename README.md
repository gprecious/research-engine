# research-engine

Deep research via Claude Code slash commands. Give it a URL or a topic — it returns a structured markdown report with citations.

## Installation

```bash
./install.sh            # symlinks to ~/.claude/plugins/research-engine
```

Then restart Claude Code or run `/plugins reload`.

## Usage

```
/research https://youtu.be/xxxxx          # analyze a YouTube video
/research https://arxiv.org/abs/2301.xxxx # analyze a paper
/research "MoE LLM trends in 2026"        # topic research
/research https://... --yes               # skip intent Q&A
/research https://... --fresh             # bypass cache

/research-followup "저자 배경 더"         # ask follow-up on latest session
/research-followup "..." --slug <name>    # target specific session
```

Output lands in `research/YYYY-MM-DD-<slug>/README.md`.

## Requirements

- `yt-dlp` in `PATH` (YouTube captions)
- `gh` CLI authenticated (GitHub)
- `jq` (JSON munging)
- Claude Code plugins: `firecrawl`, `context7`, `huggingface-skills`

## Docs

- User guide: this file
- Design spec: `docs/superpowers/specs/2026-04-16-research-engine-design.md`
- Contributor guide: `DEVELOPMENT.md`
