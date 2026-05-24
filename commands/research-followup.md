---
description: Follow up on the most recent research session (or a named one). Appends to research/<slug>/session.md.
argument-hint: "[question] [--slug <name>] [--fresh]"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, WebFetch, WebSearch
---

## Inputs

`$ARGUMENTS` — parse into:
- `question` (positional, optional). If empty, ask the user "무엇을 추가로 알고 싶으세요?" and wait.
- `--slug <name>`
- `--fresh`

## Resolve session

- If `--slug` was provided, use it.
- Else run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/find_latest_session.sh" "<project_cwd>/research"` and use that slug.
- If no session exists, tell the user: "아직 리서치 세션이 없습니다. 먼저 `/research <target>`를 실행하세요." and stop.

Let `<report_dir> = <project_cwd>/research/<slug>`.

## Load context

Read:
- `<report_dir>/README.md`
- `<report_dir>/sources.json`
- `<report_dir>/intent.json`
- `<report_dir>/session.md` (if exists; create empty if not)

## Decide: new data needed?

Classify the user's question into one of:

- **A) Answerable from existing context** — no new fetches.
- **B) Needs new fetch** — examples: "X에 대한 비교 레포 찾아줘", "저자 배경 더", "이 영상의 다른 부분".
- **C) New related thread / paper / video** — user pastes a new URL.

For (B) and (C), dispatch 1–2 adapter subagents (same contract as `/research` Stage 4) with a tightly scoped prompt. Do NOT re-run the full fan-out.

## Answer

Compose the answer in Korean. Cite existing sources by their `[n]` number from `sources.json`. If new sources were fetched, append them to `sources.json` (continue numbering), write any new `related/*.md` files, and cite with the new `[n]`.

## OCC precondition (concurrent write protection)

Before appending to `research/<slug>/session.md`:

1. Compute expected hash:
   ```bash
   expected_hash=$(sha256sum research/<slug>/session.md | awk '{print $1}')
   ```

2. Generate new content (may take seconds while LLM thinks).

3. Just before writing, recompute:
   ```bash
   actual_hash=$(sha256sum research/<slug>/session.md | awk '{print $1}')
   ```

4. If `expected_hash != actual_hash`:
   - Re-read current session.md, regenerate the new content using current state as context (1 auto-retry).
   - On second mismatch: STOP and tell the user "concurrent edit detected on `<slug>/session.md` — please re-run /research-followup after resolving the conflict manually."

5. Atomic write:
   ```bash
   cat session.md new_content > session.md.tmp
   mv session.md.tmp session.md
   ```

This OCC protects against multi-pane (`cmux:cmux-orchestrator`) scenarios where two `/research-followup` calls could race on the same session.

## Append to session.md

Append (append-only, never rewrite prior entries):

```markdown
---

## <ISO_timestamp> — <question, one line>

**질문**: <full question>

**답변**
<answer body with [n] citations>

**새 자료** (있을 때만)
- [{{title}}]({{url}}) — <one-line why>
```

## Push to Notion (mirror)

If `NOTION_TOKEN` + `NOTION_PARENT_PAGE_ID` are configured (env or `~/.config/research-engine/notion.env`), run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/push_to_notion.sh" "<report_dir>"` after `session.md` is updated. The script idempotently syncs every sub-page — existing pages are reused by title, not duplicated.

## Report path

Final message: one line with `<report_dir>/session.md` path (plus Notion URL if pushed).
