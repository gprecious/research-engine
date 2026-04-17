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

## Report path

Final message: one line with `<report_dir>/session.md` path.
