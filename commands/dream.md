---
description: Extract cross-session patterns from past /research sessions. Writes readonly insights to docs/dreams/<run-id>/.
argument-hint: "[--since=14d | --slugs=a,b,c] [--bench=<bench-run-id>]"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# `/dream`

Extract cross-session patterns from past `/research` sessions, write readonly insights to `docs/dreams/<run-id>/`.

## Inputs

- `/dream` — default: 최근 dream 이후 누적 전체 (`dream-ledger.sessions_since_last_dream`)
- `/dream --since=14d` — 최근 14일 내 세션
- `/dream --slugs=a,b,c` — 명시 슬러그 (콤마 구분)
- `/dream --bench=<bench-run-id>` — bench 결과를 입력 데이터로 추가 (옵션)

## Constants

- `${CLAUDE_PLUGIN_ROOT}` = plugin root, exported by Claude Code into each Bash tool invocation for commands owned by this plugin.
- MANIFEST = `research/_index/manifest.json`
- LEDGER = `research/_index/dream-ledger.json`

## Pipeline

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
```

## Failure handling

- **Agent returns non-JSON / malformed**: 1회 자동 재시도 + 엄격한 prompt. 2회 실패 → `docs/dreams/<RUN_ID>/FAILED.md` 작성, ledger 미업데이트, 종료.
- **빈 patterns**: 정상 완료, README.md에 "no significant patterns found across N inputs" 노트, ledger 업데이트.
- **타임아웃 5분 초과** (기본 어댑터 타임아웃 동일): JSON 파싱 실패와 동일 처리.
