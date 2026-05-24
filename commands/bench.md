---
description: research-engine vs baseline mini-bench. Runs N topics × 2 modes × 2 trials, scores via LLM-as-judge, emits report.md with improvement opportunities.
argument-hint: "[--topic <id>] [--mode re|baseline] [--n 1|2] [--force] [--no-judge] [--judge-only] [--report-only] [--check]"
allowed-tools: Bash, Read, Write, Edit, Skill, Agent
---

## Architecture note

`claude -p` does not invoke plugin slash commands non-interactively, so the bench cannot spawn isolated `claude -p` subprocesses for the run matrix. Instead, the matrix is orchestrated **inside this Claude Code session**:

- **RE mode**: invoke `Skill('research-engine:research', args='<target> --fresh --yes')` and copy the resulting `research/<slug>/README.md` into the bench run directory.
- **Baseline mode**: dispatch `Agent(subagent_type='general-purpose')` with the topic's `baseline_prompt`. The subagent has no access to research-engine slash commands or skills (its toolset is the general one — WebSearch, WebFetch, Read, Write, Bash, Agent).

Non-runtime stages (preflight, judge, aggregation, report) are handled by `bench/run.sh`.

## Inputs

`$ARGUMENTS` flags:
- `--check` — preflight only, exit
- `--topic <id>` — restrict to one topic from topics.yaml
- `--mode re|baseline` — restrict to one mode
- `--n 1|2` — restrict to one trial number
- `--force` — overwrite existing run outputs
- `--no-judge` — skip Stage 4 (judge)
- `--judge-only` — skip Stages 2-3, run Stage 4-5
- `--report-only` — skip Stages 2-4, render report only
- `--judge-model <m>` — judge model (default `claude-sonnet-4-6`)

## Constants

- `${CLAUDE_PLUGIN_ROOT}` — plugin root
- `WORKTREE` — `<project_cwd>` (where the bench's runs directory lives)
- Date today: !`date -u +%Y-%m-%d`
- `RUNS_DIR` = `${WORKTREE}/bench/runs/${DATE}`

## Pipeline

Execute these stages in order. Do not skip stages.

### Stage 1 — Preflight

Run:
```
bash "${CLAUDE_PLUGIN_ROOT}/bench/run.sh" --check
```

If non-zero exit, abort and surface the error verbatim. Otherwise proceed.

If `--check` was passed by the user, stop after Stage 1.

### Stage 2 — Run matrix

Skip if `--judge-only` or `--report-only` was passed.

Read topic ids:
```
yq -r '.topics[].id' "${CLAUDE_PLUGIN_ROOT}/bench/topics.yaml"
```

Filter by `--topic` if set. For each `topic_id`:

  Read its config from topics.yaml:
  ```
  yq -r ".topics[] | select(.id==\"${topic_id}\") | {url, baseline_prompt, category}" \
       "${CLAUDE_PLUGIN_ROOT}/bench/topics.yaml"
  ```

  For each `mode` in `[re, baseline]` (filter by `--mode` if set):
    For each `n` in `[1, 2]` (filter by `--n` if set):

      Compute `run_dir = ${RUNS_DIR}/${topic_id}/${mode}/run${n}` and
              `output  = ${run_dir}/output.md`.

      If `output` exists and `--force` is NOT set: print `[skip exists] <topic_id>/<mode>/run<n>` and continue.

      `mkdir -p ${run_dir}`. Capture `start = $(date +%s)`.

      **Mode-specific execution**:

      - **RE mode** — three steps, no others. Subagents have repeatedly skipped the post-Skill bookkeeping when the steps were spread across multiple bash blocks; the helper script collapses tail-bookkeeping into one call.
        1. Snapshot:
           ```bash
           ls "${WORKTREE}/research/" 2>/dev/null | sort > /tmp/before-${topic_id}-${mode}-run${n}.txt
           ```
        2. Determine target — if `url` is null/empty, use `topic_text = topic_id` with the `topic-` prefix stripped. Otherwise use the url. Invoke `Skill('research-engine:research', args='<target> --fresh --yes')`. Follow ALL stages of /research; do not stop until Stage 5 is complete.
        3. Bookkeeping (single call):
           ```bash
           bash "${CLAUDE_PLUGIN_ROOT}/bench/post_research_bookkeeping.sh" \
             "${run_dir}" \
             "/tmp/before-${topic_id}-${mode}-run${n}.txt"
           ```
           The helper diffs current research/ against the snapshot to locate the new session, copies its README.md to `${run_dir}/output.md`, runs `collect_metrics.sh`, and emits the meta.json. On failure (no new session, missing README), writes a `status: "failed"` meta.json and exits non-zero — do NOT manually retry; the matrix continues with the failure recorded.

      - **Baseline mode**:
        Substitute `{url}` (or `{topic}` when url is null) in `baseline_prompt` with the actual value.
        Dispatch `Agent(subagent_type='general-purpose', description='bench baseline run', prompt=<resolved_baseline_prompt> + <STRICT INSTRUCTIONS BELOW>)` and capture the agent's full final response.

        STRICT INSTRUCTIONS appended to every baseline prompt (the subagent must understand its scope):
        ```
        IMPORTANT: This is a research-baseline benchmark run. Your job is to produce ONE markdown research report based on the input above. Do NOT use any research-engine slash commands (`/research`, `/research-followup`, `/research-visualize`) — they are intentionally unavailable in this run. Use only the general toolset (WebSearch, WebFetch, Read, Bash) to gather information. Output ONLY the final markdown report (no preamble, no follow-up offer).
        ```

        Write the agent's response (the markdown body, no extra commentary) to `${output}`.

      Capture `end = $(date +%s)`.

      Run metrics:
      ```
      bash "${CLAUDE_PLUGIN_ROOT}/bench/collect_metrics.sh" "${run_dir}" "${start}" "${end}"
      ```
      (`raw.json` will not exist for in-session runs, so `model_tokens` is recorded as `null` per spec §4.4 fallback. This is acceptable.)

      Print one line: `[<topic_id>/<mode>/run<n>] OK <wall_time_sec>s`.

### Stage 3 — Save state

(no-op; outputs are already on disk under `${RUNS_DIR}`)

### Stage 4 — Judge

Skip if `--no-judge` or `--report-only` was passed.

The judge ALSO runs in this session via Agent dispatch — `judge.py`'s built-in `call_claude()` uses external `claude -p` which does not resolve plugins/auth the same way and hits rate limits independently. Orchestrate judging directly:

For each topic_id (filter by `--topic`):
  Compute `td = ${RUNS_DIR}/${topic_id}`.
  Skip if not (re/run1/output.md AND baseline/run1/output.md exist).
  Skip if `td/judge.json` already exists and `--force` is NOT set.

  **Stage 4a — cross-mode comparison**:
    1. Random A/B label assignment (e.g., `[[ $((RANDOM % 2)) -eq 0 ]]` to decide whether RE is A or B).
    2. Read system prompt: `${CLAUDE_PLUGIN_ROOT}/bench/lib/judge_prompt.md`.
    3. Build user content: `## Topic id: ${topic_id}\n\n## report A\n\n<text_a>\n\n## report B\n\n<text_b>` where the texts are the contents of the two `output.md` files (re/run1 and baseline/run1) ordered by the A/B assignment.
    4. Dispatch `Agent(subagent_type='general-purpose', model='haiku', description='judge cross-mode', prompt=<system_prompt> + '\n\n---\n\n' + <user_content> + '\n\nReturn ONLY the JSON object as specified — no preamble, no fences.')` and capture the response.
    5. Parse the response as JSON. If parsing fails, retry once with stricter wording. If still fails, write a placeholder judge.json with `judge_blind: false` and continue.
    6. Decode A/B back to re/baseline based on the random assignment in step 1.

  **Stage 4b — reproducibility (if run2 exists for both modes)**:
    For each mode in [re, baseline]:
      If `${td}/${mode}/run1/output.md` AND `${td}/${mode}/run2/output.md` both exist:
        Read both files.
        Build prompt: system + `## Reproducibility judgment\nTopic: ${topic_id}\n\n## report run1\n\n<text1>\n\n## report run2\n\n<text2>`.
        Dispatch Agent and capture response.
        Parse `reproducibility` score (0-10) from JSON.
      Else: reproducibility[mode] = null.

  Write `${td}/judge.json` matching the schema in `bench/schemas/judge.schema.json`:
  ```json
  {
    "topic_id": "...",
    "judge_model": "claude-haiku-4-5 (via Agent)",
    "judged_at": "<ISO 8601 UTC>",
    "blind_label_map": {"A": "re|baseline", "B": "re|baseline"},
    "judge_blind": <true unless response contained label-leak keywords like research-engine/plugin/subagent>,
    "cross_mode": {
      "re":       {"coverage":N, "citation":N, "depth":N, "structure":N, "rationale":"..."},
      "baseline": {"coverage":N, "citation":N, "depth":N, "structure":N, "rationale":"..."}
    },
    "reproducibility": {"re": <N|null>, "baseline": <N|null>}
  }
  ```

Print: `[judge ${topic_id}] OK` or `[judge ${topic_id}] FAILED` per topic.

### Stage 5 — Aggregate + report

```
bash "${CLAUDE_PLUGIN_ROOT}/bench/run.sh" --report
```

This consolidates `judge.json` files into `${RUNS_DIR}/results.json` and renders `${RUNS_DIR}/report.md` from the template.

Print one final line:
```
✅ Bench complete. Report: ${RUNS_DIR}/report.md
```

Do not summarize or post-process the report. The user inspects it directly.

### Dream suggestion (after report.md is written)

If `research/_index/dream-ledger.json` exists and `last_dream_at < bench.started_at`, append this line to the final user message:

```bash
if [ -f "research/_index/dream-ledger.json" ]; then
  last_dream=$(jq -r '.last_dream_at // ""' research/_index/dream-ledger.json)
  bench_started=$(jq -r '.started_at // ""' "bench/runs/${BENCH_RUN_ID}/meta.json" 2>/dev/null || echo "")
  if [ -z "${last_dream}" ] || [ "${last_dream}" \< "${bench_started}" ]; then
    echo "💡 새 bench 결과: /dream --bench=${BENCH_RUN_ID} 로 어댑터 약점을 인사이트로 전환할 수 있어요."
  fi
fi
```

자동 트리거는 *하지 않는다* — 사용자가 명시 호출해야 함.

## Failure handling

Per spec §6: any single run failure must NOT abort the matrix. If a Skill or Agent invocation throws, write the failure to `${run_dir}/meta.json` with `status: "failed"` and continue to the next iteration. Surface failures in the per-run echo line (e.g., `[<id>/<mode>/run<n>] FAILED — continuing`). Stages 4–5 still run on whatever completed.

If preflight fails (Stage 1 non-zero exit), abort immediately — do not proceed.
