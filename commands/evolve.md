---
description: research-engine 어댑터 페르소나의 evolvable 영역을 mutate하거나, wiki schema 후보를 draft로 생성.
argument-hint: "[adapter-name [region-id]] [--target=wiki --region=page-rules]"
allowed-tools: Bash, Read, Write, Edit, Agent, Skill
---

## Inputs

`$ARGUMENTS` :
- positional 1 (선택): adapter name (default: dream-ledger 의 가장 약한 어댑터 — 일단 v1 은 사용자가 명시)
- positional 2 (선택): region id (default: 첫 번째 evolvable region)
- `--target=wiki --region=<region>`: wiki evolvable region 후보를 `_drafts/_schema/` 에 생성

## Constants

- `${CLAUDE_PLUGIN_ROOT}` — plugin root
- `WORKTREE` — `<project_cwd>`
- `LEDGER` = `${WORKTREE}/research/_index/evolve-ledger.json`
- `AGENTS` = `${WORKTREE}/agents`
- `WIKI_VAULT` = `$(node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/vault_resolve.mjs")`

## Pipeline

## Wiki target branch (`--target=wiki`)

기본 adapter evolve pipeline 은 변경하지 않는다. `$ARGUMENTS` 에 `--target=wiki` 가 있으면 아래 절차만 수행한다.

### WE1 — Resolve wiki evolvable region

wiki evolvable region 은 `VAULT/AGENTS.md` 의 명시 구역과 librarian 휴리스틱이다. 예:

```md
<!-- evolvable:page-rules -->
...
<!-- /evolvable -->
```

```bash
VAULT="$(node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/vault_resolve.mjs")"
node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/wiki_evolve.mjs" \
  --vault "${VAULT}" \
  --prepare \
  --region <region|page-rules> > /tmp/wiki-evolve-input.json
```

입력에는 현재 region body, `_index/reflect_state.json`, `change_log.md` lint/librarian 추세가 들어간다.

### WE2 — Dispatch prompt-mutator Agent

Agent tool 로 `prompt-mutator` 에 `/tmp/wiki-evolve-input.json` 을 전달한다. 지시:
- AGENTS.md의 페이지 포맷, 링크 규칙, 태깅 규칙, librarian 휴리스틱 중 지정 region 만 개선한다.
- dream 산출과 lint 반복 추세를 근거로 후보 1~3개를 만든다.
- live `AGENTS.md` 를 직접 수정하지 않는다.

반환 JSON 을 `/tmp/wiki-evolve-mutator.json` 에 저장한다:

```json
{
  "variants": [
    { "body": "candidate markdown body", "rationale": "why this helps" }
  ]
}
```

### WE3 — Deterministic draft write

```bash
node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/wiki_evolve.mjs" \
  --vault "${VAULT}" \
  --apply-candidate /tmp/wiki-evolve-mutator.json \
  --region <region|page-rules> \
  --date <today>
```

산출은 `_drafts/_schema/agents-<region>.candidate.md` 와 `_index/evolve-ledger.json` append 이다. live `AGENTS.md` 는 변경하지 않는다. schema 변경은 promote/수동 검토 전까지 항상 draft 상태로 둔다.

### E1 — Resolve target

Adapter name 과 region id 가 둘 다 인자로 들어오면 그대로 사용. 하나라도 누락이면 사용자에게 묻는다 (AskUserQuestion 또는 즉시 종료 with usage).

### E2 — Prepare mutator input

```
bash scripts/evolve_run.sh prepare <name> <region> > /tmp/mutator-in.json
```

### E3 — Dispatch prompt-mutator agent

Agent tool 로 `prompt-mutator` 페르소나에 `/tmp/mutator-in.json` 의 내용을 prompt 본문으로 전달. 반환 JSON 을 `/tmp/mutator-out.json` 에 저장. 출력에 fenced JSON 블록이 없으면 1회 재시도. 2회 연속 실패 → 종료 with FAIL 메시지.

### E4 — Apply variant 0 to candidate file

```
bash scripts/evolve_run.sh apply <name> <region> /tmp/mutator-out.json
# → agents/<name>.candidate.md
```

### E5 — Multi-seed bench (current vs candidate)

bench Skill 호출 — current 와 candidate 양쪽에 동일 topic 매트릭스로 N=8 seed 권장 (현재 매트릭스가 2 trial 만 지원하면 같은 topic 을 4 번 반복 등가):

```
Skill('research-engine:bench', args='--mode re --n 8 --topic <topic-id>')
# current 결과 → /tmp/bench-current.json (judge scores 배열 + source 메트릭)
Skill('research-engine:bench', args='--mode re --n 8 --topic <topic-id> --candidates <name>:agents/<name>.candidate.md')
# candidate 결과 → /tmp/bench-candidate.json
```

bench 결과 파싱은 `bench/runs/<date>/...` 의 score JSON 을 jq 로 집계. 정확한 키는 기존 bench/run.sh report stage 와 동일 키 사용.

### E6 — Decide

```
bash scripts/evolve_run.sh decide <name> /tmp/bench-current.json /tmp/bench-candidate.json
```

stdout JSON 의 `decision` 필드를 읽는다.

### E7 — Promote or rollback

- `accept` → `bash scripts/evolve_run.sh promote <name>` 호출. ledger 는 E6 에서 이미 promote 처리됨. 이 단계는 파일만 swap.
- `reject` 또는 `hold` → `agents/<name>.candidate.md` 삭제. ledger 는 E6 에서 이미 처리됨 (hold 는 ledger 무변경).

### E8 — Final message

한 줄 요약 + ledger path + 채택 시 새 version, hold 시 frontier 위치 노출.

## Failure policy

- mutator JSON 파싱 실패 2회 → 종료, ledger 미수정.
- bench 매트릭스 실패 → 종료, candidate 파일 정리.
- decide 후 promote 단계에서 파일 swap 실패 (e.g., 권한) → ledger 롤백 (history pop) + 사용자 알림.
