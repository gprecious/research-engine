#!/usr/bin/env bats

# These tests exercise bench/run.sh --swap-candidates / --restore-candidates.
# BENCH_REPO_ROOT_OVERRIDE points the script at a temp dir so the real
# agents/ directory is never touched.

setup() {
  PROJECT_DIR="$(pwd)"
  WORK=$(mktemp -d)
  mkdir -p "$WORK/agents"
}

teardown() { rm -rf "$WORK"; }

@test "swap-candidates: agent file replaced, backup recorded" {
  echo "ORIGINAL" > "$WORK/agents/foo.md"
  echo "CANDIDATE" > "$WORK/cand.md"

  BENCH_REPO_ROOT_OVERRIDE="$WORK" \
    bash "$PROJECT_DIR/bench/run.sh" --swap-candidates "foo:$WORK/cand.md"

  [ "$(cat "$WORK/agents/foo.md")" = "CANDIDATE" ]
  [ -f "$WORK/.bench-restore/foo.md" ]
  [ "$(cat "$WORK/.bench-restore/foo.md")" = "ORIGINAL" ]
  grep -q "foo:$WORK/cand.md" "$WORK/.bench-restore/_specs.txt"
}

@test "restore-candidates: agent file restored, restore dir cleaned" {
  echo "ORIGINAL" > "$WORK/agents/foo.md"
  echo "CANDIDATE" > "$WORK/cand.md"

  BENCH_REPO_ROOT_OVERRIDE="$WORK" \
    bash "$PROJECT_DIR/bench/run.sh" --swap-candidates "foo:$WORK/cand.md"
  BENCH_REPO_ROOT_OVERRIDE="$WORK" \
    bash "$PROJECT_DIR/bench/run.sh" --restore-candidates

  [ "$(cat "$WORK/agents/foo.md")" = "ORIGINAL" ]
  [ ! -d "$WORK/.bench-restore" ]
}

@test "swap-candidates: refuses to overwrite an existing swap" {
  echo "ORIGINAL" > "$WORK/agents/foo.md"
  echo "CANDIDATE" > "$WORK/cand.md"

  BENCH_REPO_ROOT_OVERRIDE="$WORK" \
    bash "$PROJECT_DIR/bench/run.sh" --swap-candidates "foo:$WORK/cand.md"

  run env BENCH_REPO_ROOT_OVERRIDE="$WORK" \
    bash "$PROJECT_DIR/bench/run.sh" --swap-candidates "foo:$WORK/cand.md"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "previous swap not restored"
}

@test "swap-candidates: missing agent file aborts and reverts partial swaps" {
  echo "A" > "$WORK/agents/a.md"
  echo "CAND_A" > "$WORK/cand-a.md"
  echo "CAND_MISSING" > "$WORK/cand-missing.md"

  run env BENCH_REPO_ROOT_OVERRIDE="$WORK" \
    bash "$PROJECT_DIR/bench/run.sh" \
    --swap-candidates "a:$WORK/cand-a.md missing:$WORK/cand-missing.md"
  [ "$status" -ne 0 ]
  [ "$(cat "$WORK/agents/a.md")" = "A" ]
  [ ! -d "$WORK/.bench-restore" ]
}

@test "swap-candidates: supports multiple pairs" {
  echo "A" > "$WORK/agents/a.md"
  echo "B" > "$WORK/agents/b.md"
  echo "CAND_A" > "$WORK/cand-a.md"
  echo "CAND_B" > "$WORK/cand-b.md"

  BENCH_REPO_ROOT_OVERRIDE="$WORK" \
    bash "$PROJECT_DIR/bench/run.sh" \
    --swap-candidates "a:$WORK/cand-a.md b:$WORK/cand-b.md"

  [ "$(cat "$WORK/agents/a.md")" = "CAND_A" ]
  [ "$(cat "$WORK/agents/b.md")" = "CAND_B" ]

  BENCH_REPO_ROOT_OVERRIDE="$WORK" \
    bash "$PROJECT_DIR/bench/run.sh" --restore-candidates

  [ "$(cat "$WORK/agents/a.md")" = "A" ]
  [ "$(cat "$WORK/agents/b.md")" = "B" ]
}

@test "restore-candidates is a no-op when nothing to restore" {
  run env BENCH_REPO_ROOT_OVERRIDE="$WORK" \
    bash "$PROJECT_DIR/bench/run.sh" --restore-candidates
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "nothing to restore"
}
