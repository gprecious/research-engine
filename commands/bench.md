---
description: research-engine vs baseline mini-bench. Runs 5 topics × 2 modes × N=2, scores via LLM-as-judge, emits report.md with improvement opportunities.
argument-hint: "[--topic <id>] [--mode re|baseline] [--force] [--no-judge] [--judge-only] [--report-only] [--judge-model <m>] [--check]"
allowed-tools: Bash, Read
---

## Inputs

`$ARGUMENTS` is forwarded verbatim to `bench/run.sh`. See `bench/run.sh --help` for the full flag list.

## What this does

Runs the mini-bench described in `docs/superpowers/specs/2026-04-26-research-engine-bench-design.md`. Wall time for the full matrix is ~3 hours. Use `--topic smoke --no-judge` for a 1–2 minute plumbing smoke test before launching the real thing.

## Execution

Run:

```
bash "${CLAUDE_PLUGIN_ROOT}/bench/run.sh" $ARGUMENTS
```

Stream the output back to the user as it arrives. When the run finishes, point them to the final report path printed in the last `✅ Bench complete.` line. Do NOT post-process or summarize the report — the user inspects it directly.

If preflight fails (non-zero exit before any matrix run), surface the error verbatim and stop.
