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

      - **RE mode**:
        Determine target — if `url` is null/empty, use `topic_text = topic_id` with the `topic-` prefix stripped (e.g., `topic-mamba` → `mamba`). Otherwise use the url.
        Invoke `Skill('research-engine:research', args='<target> --fresh --yes')`.
        After /research's full pipeline finishes, the report dir is at `${WORKTREE}/research/<latest>/`. Find the most recent session dir:
        ```
        latest=$(ls -td "${WORKTREE}/research/"*/ 2>/dev/null | head -1)
        ```
        Copy `${latest}/README.md` to `${output}`.
        If `${latest}/README.md` does not exist, write a single-line `output.md` containing `RE mode produced no README.md` and mark the run as failed in meta.json (set `status: "failed"`, `exit_code: 1`).

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

```
bash "${CLAUDE_PLUGIN_ROOT}/bench/run.sh" --judge ${ONLY_TOPIC:+--topic "$ONLY_TOPIC"} ${FORCE:+--force} --judge-model "${JUDGE_MODEL}"
```

This iterates populated topic dirs and invokes `judge.py` for each. Already-judged topics are skipped unless `--force`.

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

## Failure handling

Per spec §6: any single run failure must NOT abort the matrix. If a Skill or Agent invocation throws, write the failure to `${run_dir}/meta.json` with `status: "failed"` and continue to the next iteration. Surface failures in the per-run echo line (e.g., `[<id>/<mode>/run<n>] FAILED — continuing`). Stages 4–5 still run on whatever completed.

If preflight fails (Stage 1 non-zero exit), abort immediately — do not proceed.
