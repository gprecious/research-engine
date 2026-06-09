---
description: Extract cross-session patterns from past /research sessions. Writes readonly insights to docs/dreams/<run-id>/, or wiki drafts with --target=wiki.
argument-hint: "[--since=14d | --slugs=a,b,c] [--bench=<bench-run-id>] [--target=wiki]"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# `/dream`

Extract cross-session patterns from past `/research` sessions, write readonly insights to `docs/dreams/<run-id>/`.

## Inputs

- `/dream` — default: 최근 dream 이후 누적 전체 (`dream-ledger.sessions_since_last_dream`)
- `/dream --since=14d` — 최근 14일 내 세션
- `/dream --slugs=a,b,c` — 명시 슬러그 (콤마 구분)
- `/dream --bench=<bench-run-id>` — bench 결과를 입력 데이터로 추가 (옵션)
- `/dream --target=wiki` — Obsidian LLM Wiki concepts/entities 를 입력으로 synthesis draft + todo 를 생성

## Constants

- `${CLAUDE_PLUGIN_ROOT}` = plugin root, exported by Claude Code into each Bash tool invocation for commands owned by this plugin.
- MANIFEST = `research/_index/manifest.json`
- LEDGER = `research/_index/dream-ledger.json`
- WIKI_VAULT = `$(node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/vault_resolve.mjs")`

## Pipeline

## Wiki target branch (`--target=wiki`)

기본 `/dream` research-session pipeline 은 변경하지 않는다. `$ARGUMENTS` 에 `--target=wiki` 가 있으면 아래 절차만 수행한다.

### W1 — Resolve wiki corpus

```bash
VAULT="$(node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/vault_resolve.mjs")"
node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/wiki_dream.mjs" --vault "${VAULT}" --corpus > /tmp/wiki-dream-corpus.json
```

입력 코퍼스는 live `concepts/`, `entities/` 의 slug/title/type/sources/related/TL;DR 요약만이다. `_drafts/` 는 제외한다.

### W2 — Discovery Agent

Agent tool 로 dream-extractor 에 `/tmp/wiki-dream-corpus.json` 을 전달한다. 지시:
- cross-cutting theme, implicit connection, contradiction, coverage gap 후보 3~5개를 찾는다.
- synthesis 후보는 반드시 evidence page slug 2개 이상을 갖는다.
- gap 은 `_todos/<topic>.md` 에 들어갈 research question 으로 쓴다.

반환 JSON 을 `/tmp/wiki-dream-output.json` 에 저장한다:

```json
{
  "synthesis": {
    "slug": "ascii-kebab",
    "title": "Title",
    "summary": "short sourced summary",
    "evidenceSlugs": ["page-a", "page-b"],
    "sources": ["research/a", "research/b"],
    "confidence": "medium"
  },
  "todo": {
    "slug": "ascii-kebab-gap",
    "title": "Gap title",
    "question": "new research question"
  }
}
```

### W3 — Deterministic write

```bash
node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/wiki_dream.mjs" \
  --vault "${VAULT}" \
  --apply /tmp/wiki-dream-output.json \
  --date <today>
```

산출은 항상 `_drafts/synthesis/<slug>.md` 와 `_todos/<topic>.md` 이며, `type: synthesis`, `tags: [ai-generated, llm-wiki, synthesis]`, evidence page related links, `_index/reflect_state.json` 증분을 보장한다. synthesis 는 promote 전 live index/graph 에 올리지 않는다.

### D1 — Resolve inputs

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/dream_run.sh" --resolve-only [--slugs ... | --since ...]
```

If exit non-zero with "not enough sessions" — STOP and tell the user. Do not mint a dream from <2 sessions.

### D2 — Mint run_id + directory

```bash
MINT_JSON=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/dream_run.sh" --mint-only [args])
RUN_ID=$(echo "${MINT_JSON}" | jq -r '.run_id')
```

Creates `docs/dreams/<RUN_ID>/{meta.json,insights/}`.

### D3 — Dispatch dream-extractor (Agent tool)

Prepare input JSON:

```bash
MANIFEST_EXCERPT=$(jq --argjson resolved "$(echo "${MINT_JSON}" | jq '.resolved')" '
  {sessions: [.sessions[] | select(.slug as $s | $resolved | index($s))]}
' "${MANIFEST}")

INTENT_DIST=$(echo "${MANIFEST_EXCERPT}" | jq '
  {
    by_focus: ([.sessions[].intent.focus] | group_by(.) | map({(.[0]): length}) | add),
    by_audience: ([.sessions[].intent.audience_level] | group_by(.) | map({(.[0]): length}) | add)
  }')

AGENT_INPUT=$(jq -nc \
  --arg run_id "${RUN_ID}" \
  --argjson session_paths "$(echo "${MANIFEST_EXCERPT}" | jq '[.sessions[].path]')" \
  --argjson manifest_excerpt "${MANIFEST_EXCERPT}" \
  --argjson intent_distribution "${INTENT_DIST}" \
  '{run_id: $run_id, session_paths: $session_paths, manifest_excerpt: $manifest_excerpt, intent_distribution: $intent_distribution, bench_excerpt: null}')
```

Dispatch via Agent tool:

```
Agent(
  description: "dream-extractor for <RUN_ID>",
  subagent_type: "research-engine:dream-extractor",
  prompt: "You are dispatched as the dream-extractor subagent for run <RUN_ID>.\n\nInputs:\n  <AGENT_INPUT>\n\nReturn a single fenced JSON block per the contract in agents/dream-extractor.md."
)
```

Save agent's JSON to `/tmp/dream-output-${RUN_ID}.json`.

### D4–D7 — Finalize

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/dream_run.sh" --finalize \
  --run-id "${RUN_ID}" \
  --agent-output "/tmp/dream-output-${RUN_ID}.json"
```

Splits patterns into `insights/pattern-*.md`, writes `README.md` (frontmatter status=active), writes `sources.json` (input slugs + sha256), resets `dream-ledger.json`, runs `memory_reindex.sh`.

### D8 — Final user message

```
📄 docs/dreams/<RUN_ID>/README.md
2줄 TL;DR (from strongest pattern)
N개 insight 파일 생성됨 — 부적절한 것은 README frontmatter의 status를 discarded로 변경하세요.
💡 추출된 인사이트 중 adapter_failure_modes 항목이 있으면 `/evolve <adapter-name>` 으로 해당 어댑터 페르소나 진화 시도 가능.
```

## Failure handling

- **Agent returns non-JSON / malformed**: 1회 자동 재시도 + 엄격한 prompt. 2회 실패 → `docs/dreams/<RUN_ID>/FAILED.md` 작성, ledger 미업데이트, 종료.
- **빈 patterns**: 정상 완료, README.md에 "no significant patterns found across N inputs" 노트, ledger 업데이트.
- **타임아웃 5분 초과** (기본 어댑터 타임아웃 동일): JSON 파싱 실패와 동일 처리.
