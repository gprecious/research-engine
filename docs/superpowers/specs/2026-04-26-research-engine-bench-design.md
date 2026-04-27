# research-engine vs Claude Code baseline — mini-bench design

**Date**: 2026-04-26
**Status**: design approved, awaiting implementation plan
**Goal**: A repeatable mini-benchmark that compares `research-engine` slash commands against a vanilla Claude Code baseline on the same set of topics, scores both with a structured 5-axis rubric, and surfaces concrete improvement opportunities for the next research-engine PR cycle.

---

## 1. Motivation and scope

We have shipped 8 real research sessions under `research/` and several visualization features, but we have no quantitative or qualitative signal for how much value the research-engine prompt engineering, adapters, and orchestration actually adds over a user's natural fallback ("just ask Claude Code with general-purpose agent"). Without that signal:

- We cannot prioritize which adapter (YouTube / arXiv / GitHub / blog / topic-only) needs work first.
- Future PRs land without a regression check — a refactor could quietly degrade output quality and we would not notice.
- Improvement claims in PR descriptions are unverifiable.

This spec defines a **mini-bench**: small enough to be manually triggered today, structured enough to be re-run on future commits as a smoke comparison.

**In scope**: One bench harness invoked via `/bench` slash command, producing a markdown report with score deltas and an "improvement opportunities" section.

**Out of scope (future work)**: CI integration, statistical significance testing, parallel run execution, third-party judge validation.

---

## 2. Decisions and rationale

| Decision | Choice | Why |
|---|---|---|
| Baseline definition | Claude Code + `general-purpose` subagent, no research-engine plugin | Closest to real-user fallback behavior; avoids comparing against an artificially weak baseline (vanilla WebFetch only) |
| Topic set | 5 categories × 1 each: YouTube / arXiv / GitHub / blog / topic-only | Surfaces per-adapter weaknesses; minimum coverage for meaningful generalization |
| Rubric | 5 axes 0–10 weighted to 0–100: **Coverage / Citation Quality / Depth / Structure / Reproducibility** + auxiliary quantitative metrics (wall time, word count, citation count, link count, model tokens) | Visualizer-judge's 4 axes are visualization-specific (Design Quality is irrelevant for text); a research-specific rubric is needed |
| Judge | LLM-as-judge via `claude -p --model sonnet-4-6`, blind A/B labels, swap order randomized | Removes manual scoring labor; blinding removes label bias |
| Execution | `claude -p` non-interactive, one subprocess per run, serial | Strongest isolation between sessions; no context leak; trivially scriptable |
| Trials per topic | N=2 | Reproducibility axis requires N≥2; N=3 is over-investment for a first bench |
| Total runs | 5 topics × 2 modes × 2 trials = 20 runs | ~3.3h wall time at ~10 min/run average |
| Code structure | Approach A: `bench/` shell harness + `commands/bench.md` slash command + `bench/judge.py` | Matches existing `scripts/*.sh` + `commands/*.md` repo idiom; slash command is discoverable |
| Notion push during bench | Forced off via `NOTION_TOKEN=` empty env | Bench should not pollute the Notion workspace |
| `/research` cache | Forced fresh via `--fresh` flag | N=2 reproducibility measurement requires non-cached runs |

---

## 3. Architecture

```
User ─────► /bench [args]                          (Claude Code slash command)
                │
                ▼
         commands/bench.md                          (thin orchestrator prompt)
                │  Bash invocation
                ▼
         bench/run.sh ───────► claude -p "/research <topic> --fresh"   (RE mode, N=2)
                │              claude -p "<baseline_prompt>"           (baseline mode, N=2)
                │                  │
                │                  ▼  stdout/stderr captured
                │     bench/runs/<date>/<topic>/<mode>/run{1,2}/output.md
                │                  │
                │     bench/collect_metrics.sh  → meta.json
                │                  │
                ▼                  ▼
         bench/judge.py  ◄── meta.json + output.md
                │
                │  claude -p (LLM-as-judge, sonnet-4-6 default)
                │  blind A/B comparison, 5-axis 0–10 scores
                ▼
         bench/runs/<date>/results.json   (all runs × axes aggregated)
                │
                ▼
         bench/runs/<date>/report.md      (human-readable summary + improvements)
```

### 3.1 Key architectural decisions

1. **Slash command is a thin entry point.** `commands/bench.md` only invokes `bench/run.sh` via Bash and forwards progress to stdout. All heavy logic lives in shell + Python.
2. **Each run is an isolated `claude -p` subprocess.** Zero session-context leak between runs. For baseline runs, research-engine is disabled via `RESEARCH_ENGINE_DISABLE=1` env var (and `claude -p --no-plugins` if the CLI supports it — to be verified during plan spike).
3. **Judge is also a `claude -p` subprocess.** Model overridable via `--judge-model`; default `sonnet-4-6`. Output forced to strict JSON via system prompt.
4. **All runs are idempotent.** `bench/runs/<date>/<topic>/<mode>/run<n>/` already populated → skip; `--force` to overwrite. Allows resuming after partial failure.

### 3.2 Isolation mechanism

- **Plugin isolation**: `RESEARCH_ENGINE_DISABLE=1` env (or `--no-plugins` flag if available) when invoking baseline runs, so the baseline does not see research-engine slash commands, agents, or skills.
- **Notion isolation**: Both modes invoked with `NOTION_TOKEN=` (empty) so the `/research` Notion-push step is a silent no-op and the baseline cannot accidentally push either.
- **Model parity**: Both modes invoked against the same model (default: whatever `claude -p` resolves to, typically `claude-opus-4-7`). Configurable via `--model`.
- **Cache isolation**: RE mode always uses `/research --fresh`; baseline mode has no analogous cache.

---

## 4. Components

### 4.1 `bench/topics.yaml` — input contract

```yaml
- id: youtube-<slug>
  category: youtube
  url: https://www.youtube.com/watch?v=<id>
  baseline_prompt: |
    이 YouTube 영상에 대한 deep research 를 해줘. 핵심 주장, 인용, 한계점 포함한
    구조화된 markdown 리포트를 만들어줘: <url>

- id: arxiv-<slug>
  category: arxiv
  url: https://arxiv.org/abs/<id>
  baseline_prompt: |
    이 논문에 대한 deep research 리포트를 만들어줘: <url>

- id: github-<slug>
  category: github
  url: https://github.com/<owner>/<repo>
  baseline_prompt: |
    이 GitHub 저장소를 분석해줘 — 목적, 구조, 활성도, 사용 사례: <url>

- id: blog-<slug>
  category: blog
  url: https://<host>/<post>
  baseline_prompt: |
    이 블로그/문서 페이지에 대한 deep research: <url>

- id: topic-<slug>
  category: topic
  url: null
  baseline_prompt: |
    "<keyword>" 에 대한 deep research 리포트를 만들어줘. 최신 동향, 주요 플레이어,
    인용 포함.

# Smoke topic — used by `bench/run.sh --topic smoke --no-judge` for plumbing validation.
- id: smoke
  category: arxiv
  url: https://arxiv.org/abs/<short-paper-id>
  baseline_prompt: |
    이 논문에 대한 deep research 리포트를 만들어줘: <url>
```

**Fairness rule**: every `baseline_prompt` shares only the three keywords "deep research" + "구조화된 markdown" + "인용 포함" (or near-equivalents). Any extra guidance constitutes leaking research-engine prompt design into the baseline → unfair.

### 4.2 `commands/bench.md` — slash command entry

`/bench` (full matrix) / `/bench --topic <id>` (single topic) / `/bench --judge-only` (re-judge existing runs) / `/bench --report-only` (regenerate report from existing results.json). The command body is short: invoke `bash bench/run.sh "$@"` via Bash, stream progress, then point user to the final report.

### 4.3 `bench/run.sh` — orchestrator

Flags:
- `--topic <id>` — restrict to one topic
- `--mode re|baseline` — restrict to one mode
- `--force` — overwrite existing run outputs
- `--no-judge` — skip judge stage (for smoke / plumbing tests)
- `--check` — run preflight environment validation only
- `--judge-only` — assume runs exist, only run judge
- `--report-only` — assume judge done, only regenerate report

Inner loop pseudocode:

```bash
for topic in $(yq '.[].id' bench/topics.yaml); do
  for mode in re baseline; do
    for n in 1 2; do
      out_dir=bench/runs/$DATE/$topic/$mode/run$n
      [ -f $out_dir/output.md ] && [ "$FORCE" != 1 ] && continue
      mkdir -p $out_dir
      start=$(date +%s)

      env $extra_env_for_mode \
        NOTION_TOKEN= \
        timeout 1800 \
        claude -p "$prompt" \
        > $out_dir/output.md 2> $out_dir/stderr.log \
        || echo '{"status":"failed"}' > $out_dir/meta.json

      end=$(date +%s)
      bench/collect_metrics.sh "$out_dir" "$start" "$end"
    done
  done
done

bench/judge.py --all
bench/report.py --date $DATE
```

Serial execution only in v1. Parallel execution flagged as future work.

### 4.4 `bench/collect_metrics.sh` — quantitative auto-collection

Reads `output.md` and `stderr.log`, writes `meta.json`:

```json
{
  "status": "ok",
  "wall_time_sec": 612,
  "word_count": 2843,
  "citation_count": 17,
  "external_link_count": 23,
  "model_tokens": {"input": 45200, "output": 8910},
  "exit_code": 0
}
```

`model_tokens` parsed from `claude -p` output if exposed (verify during plan spike); else recorded as `null` and excluded from comparisons.

### 4.5 `bench/judge.py` — LLM-as-judge

Two stages per topic:

**Stage 4a — Cross-mode comparison (Coverage / Citation / Depth / Structure)**

Only `run1` from each mode is judged cross-mode. `run2` is reserved for the reproducibility axis (Stage 4b). This keeps the judge call count tractable (5 topics × 1 cross-mode call + 5 topics × 2 reproducibility calls = 15 judge calls) and avoids the cherry-picking pitfall of "best of run1/run2".

```python
for topic in topics:
    a, b = random.sample([("re", re_run1), ("baseline", baseline_run1)], 2)
    prompt = build_judge_prompt(label_A=a[1], label_B=b[1], topic=topic)
    resp = claude_p(prompt, model=judge_model, system=STRICT_JSON_SYSTEM)
    scores = parse_json(resp)
    save_with_decoded_labels(topic, scores, a, b)   # writes runs/<date>/<topic>/judge.json
```

System prompt forces JSON-only output with one-line rationale per axis. Random A/B swap removes label-position bias.

**Stage 4b — Reproducibility (run1 vs run2 within same mode)**

A separate judge call per (topic, mode), so two calls per topic — one for `re`, one for `baseline`:
> "Score 0–10 on consistency between two outputs for the same input. Do core facts agree? Do cited sources overlap? Is structure similar?"

Each mode gets its own reproducibility score (the 5th axis). Both are appended to the same `judge.json`.

### 4.6 `bench/runs/<date>/results.json` — aggregated schema

```json
{
  "bench_date": "2026-04-26",
  "judge_model": "claude-sonnet-4-6",
  "topics": [
    {
      "id": "youtube-<slug>",
      "re": {
        "run1": {"meta": {...}, "output_path": "..."},
        "run2": {...},
        "scores": {"coverage": 8.5, "citation": 9.0, "depth": 8.0, "structure": 9.0, "reproducibility": 8.5},
        "weighted_total": 86.0
      },
      "baseline": {
        "run1": {...}, "run2": {...},
        "scores": {...},
        "weighted_total": 62.0
      },
      "delta": 24.0,
      "judge_rationale": "..."
    }
  ],
  "aggregate": {
    "re_avg": 84.2,
    "baseline_avg": 61.0,
    "delta_avg": 23.2,
    "by_axis": {"coverage": {...}, "citation": {...}, ...},
    "by_category": {"youtube": {...}, ...}
  }
}
```

### 4.7 `bench/report.py` and `bench/runs/<date>/report.md` — human-facing output

`report.py` reads `results.json` and renders `report.md` from a template. Sections:

1. **Executive summary** — 5-axis bar chart (mermaid), per-topic delta table.
2. **Per-category detail** — for each of the 5 topics: A/B excerpt, judge rationale, score breakdown.
3. **Improvement opportunities** — auto-extracted: any axis where baseline ≥ RE (regression candidates), any axis where RE scored ≤6 (weak spots), low reproducibility adapters.
4. **Methodology and limitations** — bench command, models, dataset, known caveats (see §7).

---

## 5. Data flow

End-to-end timeline of one full `/bench` invocation:

1. **Entry** — User runs `/bench` in Claude Code. `commands/bench.md` is loaded; the command invokes `bash bench/run.sh` via Bash.
2. **Preflight** — `run.sh` validates environment (claude CLI, yt-dlp, jq, yq, writable dirs, `NOTION_TOKEN` unset). Aborts immediately on missing dependencies — no half-completed bench.
3. **Run matrix** — Serial loop over 20 runs (5 topics × 2 modes × 2 trials). Each spawns a `claude -p` subprocess with 30-min timeout. Stdout → `output.md`, stderr → `stderr.log`. After each run, `collect_metrics.sh` writes `meta.json`. Idempotent: existing `output.md` → skip unless `--force`.
4. **Judge** — After all runs, `judge.py` does Stage 4a (cross-mode A/B) and Stage 4b (reproducibility), writing `judge.json` per topic.
5. **Aggregate + report** — `results.json` consolidates everything; `report.md` rendered from template.
6. **Handoff** — Slash command prints final summary and report path.

**State residency**:
- Persistent (across sessions): everything under `bench/runs/<date>/`.
- Ephemeral (current session): progress stream from the slash command.

**Wall time budget**: ~3.3 hours for full matrix at 10 min/run average. User is told upfront to run as a background task.

---

## 6. Error handling

### 6.1 Failure matrix

| Failure | Where | Detection | Response |
|---|---|---|---|
| `claude -p` timeout (1800s) | run.sh | exit code 124 | meta.json `status: timeout`, continue |
| `claude -p` non-zero exit | run.sh | exit code ≠ 0 | meta.json `status: failed`, preserve stderr.log, continue |
| `--no-plugins` not supported | run.sh preflight | spike result | Fallback to env-only isolation; warn user if neither works |
| YouTube captions missing | inside `/research` | "failed" keyword in output.md | Mark this single run `status: skipped`, others continue |
| yt-dlp / firecrawl / jq / yq absent | run.sh preflight | `which` check | **Abort immediately** with actionable error message |
| `NOTION_TOKEN` accidentally set | run.sh preflight | env check | Abort immediately to prevent Notion pollution |
| Judge JSON parse failure | judge.py | `json.loads` fails | Retry once with stricter system prompt; if still fails, preserve raw response and record `score: null` |
| Judge label leakage (blindness broken) | judge.py | response contains "research-engine" / "plugin" / etc. | Warning printed; scores still recorded with `judge_blind: false` flag |
| Both run1 and run2 fail | aggregation | results.json validation | Mark topic `status: incomplete`, exclude from aggregate averages |

### 6.2 Principles

- **Partial failure must not abort the matrix.** 18/20 successful runs is still useful — the report just flags missing data.
- **Preflight failures DO abort** — better to fail in 5 seconds than 2 hours in.
- **No automatic retry of failed runs.** Failures usually indicate real bugs, not transient API issues. User manually re-runs with `--topic <id> --force`.
- **No partial-output salvage for judging.** Binary success/failure: either a complete output is judged, or the run is excluded.

---

## 7. Testing and self-validation

### 7.1 Preflight check

`bench/run.sh --check` runs the environment validation in isolation. Useful as a CI smoke and as a first thing to try when a full run fails.

### 7.2 Smoke test on cheap topic

`bench/run.sh --topic smoke --no-judge` runs 4 runs (2 modes × 2 trials) on a deliberately minimal topic (e.g., a 2-min YouTube clip or single arXiv abstract) to validate plumbing — `claude -p` invocation, output capture, metrics collection, idempotency. Expected to finish in 1–2 minutes; recommended on every PR touching the bench code.

### 7.3 Judge self-check (most important meta-test)

`bench/judge.py --self-check` feeds the *same* RE output as both A and B to the judge. Expected: |score_A − score_B| ≤ 1 on every axis. Sustained imbalance indicates judge bias on label position/order — fix the system prompt before trusting any real scores.

Re-run whenever the judge model version changes.

### 7.4 Idempotency check

Manually verify: running `bench/run.sh --topic <id>` twice in a row leaves `bench/runs/<date>/<id>/...` unchanged on the second invocation. One-off check, low regression risk.

### 7.5 Schema validation

`bench/schemas/{meta,judge,results}.json` define JSON Schema for each artifact. `judge.py` and `report.py` validate inputs at boundaries; schema violations error loudly rather than silently producing N/A.

### 7.6 Explicit non-goals

- No pytest/unittest framework — shell-heavy harness, `set -euo pipefail` + preflight + smoke is sufficient.
- No mocked `claude -p` — the CLI's behavior is the dependency under test; mocking defeats the point.
- No automated judge accuracy validation — first-pass validation is human review of sampled judge outputs.

### 7.7 Honest reporting of bench limitations

The `report.md` ends with a **Limitations** section to keep readers from over-generalizing:

- LLM-as-judge with same model family (Claude) → potential self-favoring bias.
- N=2 is too small for statistical confidence intervals.
- 5 topics = 1 per category; weak generalization across diverse content within a category.
- `baseline_prompt` phrasing is sensitive — small wording changes can move scores.

Surfacing these in the report keeps the bench's own credibility intact.

---

## 8. File layout summary

```
bench/
  topics.yaml                 # 5 production topics + 1 smoke topic
  run.sh                      # orchestrator
  collect_metrics.sh          # quantitative metric extraction
  judge.py                    # LLM-as-judge (Stage 4a + 4b + self-check)
  report.py                   # report.md generation from results.json
  schemas/
    meta.schema.json
    judge.schema.json
    results.schema.json
  runs/
    <YYYY-MM-DD>/
      <topic-id>/
        re/run{1,2}/{output.md, stderr.log, meta.json}
        baseline/run{1,2}/{output.md, stderr.log, meta.json}
        judge.json
      results.json
      report.md
commands/
  bench.md                    # /bench slash command entry
docs/superpowers/specs/
  2026-04-26-research-engine-bench-design.md   # this file
```

---

## 9. Open questions (resolve during implementation plan)

1. **`claude -p --no-plugins` availability** — verify whether the Claude Code CLI exposes a flag to disable plugin loading. If yes, use it for cleanest baseline isolation; if no, fall back to env-var-based disabling.
2. **Token usage exposure via `claude -p`** — verify whether stderr or transcript exposes token counts in non-interactive mode. If not, `model_tokens` stays `null` and the bench uses wall-time and word-count as proxies.
3. **Smoke topic selection** — pick a specific short arXiv abstract or 2-min YouTube clip during plan stage; needs to be stable (won't disappear) and cheap.
4. **Real topic URLs** — `topics.yaml` ships with `<id>` placeholders during design; concrete URLs picked during plan stage to balance representativeness vs cost.
5. **Concurrency for future PR** — measure how rate-limit-prone YouTube/firecrawl/GitHub are during serial v1; informs whether v2 parallelization is feasible.
