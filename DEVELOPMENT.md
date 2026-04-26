# Development

## Layout

See `docs/superpowers/plans/2026-04-16-research-engine.md` for the full file map and task breakdown.

## Running shell tests

```bash
sudo apt install -y bats   # one-time
bats tests/bats/
```

New bats files added in 0.3.0:
- `tests/bats/test_load_session.bats`
- `tests/bats/test_patch_readme.bats`
- `tests/bats/test_render_chart.bats`

## Manual acceptance

See `tests/acceptance/*.md` — each file is a checklist you step through in a fresh Claude Code session with the plugin installed.

### Bench tests

- `tests/bats/test_collect_metrics.bats`
- `tests/bats/test_judge.bats`
- `tests/bats/test_report.bats`
- `tests/bats/test_bench_run.bats`

Run all bench tests: `bats tests/bats/test_*.bats`
Manual acceptance: `tests/acceptance/bench.md` (created in Task 15)

## Adapter contract

All adapters return the JSON specified in `lib/adapter_contract.md`. The orchestrator (`commands/research.md`) merges these into the report.
