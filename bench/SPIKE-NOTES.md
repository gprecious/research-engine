# Spike notes — to be deleted after Task 13

## Plugin isolation finding (resolves spec §9.1)

### Discovery: `--help` output
```
--disable-slash-commands                          Disable all skills
```

- **`--disable-slash-commands` flag**: YES — native support exists in claude CLI
- **`RESEARCH_ENGINE_DISABLE=1` env var**: Not honored (research-engine does not read this env var; confirmed spec expectation)

### Test results
- Direct flag test: Aborted (API credit limit hit before receiving response)
- Env var test: Aborted (API credit limit hit before receiving response)

**Decision for run.sh**: Use `claude -p --disable-slash-commands` for baseline mode. This is a native CLI flag that disables all skills/plugins globally, including research-engine. No env-var fallback needed; the flag is reliable and well-documented in the CLI help.

## Token exposure finding (resolves spec §9.2)
- (to be filled in Task 2)
