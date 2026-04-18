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

Output lands in `research/YYYY-MM-DD-<slug>/README.md` and (when Notion is configured) mirrored to Notion at `<parent>/research-engine/<slug>/`.

## Notion mirroring (optional one-time setup)

When `NOTION_TOKEN` + `NOTION_PARENT_PAGE_ID` are set, every `/research` run auto-pushes the report as a Notion page tree (main + transcript + followups + related/*), with follow-ups idempotently appended.

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

## Requirements

- `yt-dlp` in `PATH` (YouTube captions)
- `gh` CLI authenticated (GitHub)
- `jq` (JSON munging)
- `perl` with UTF-8 support (for Unicode-aware slugify; standard on Debian/Ubuntu)
- Claude Code plugins: `firecrawl`, `context7`, `huggingface-skills`

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
