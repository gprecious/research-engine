#!/usr/bin/env bats

@test "bench --candidates swaps adapter file and restores on exit" {
  WORK=$(mktemp -d)
  mkdir -p "$WORK/agents"
  echo "ORIGINAL" > "$WORK/agents/foo.md"
  echo "CANDIDATE" > "$WORK/cand.md"

  # source 'swap' inline simulation
  CANDIDATES="foo:$WORK/cand.md"
  cp "$WORK/agents/foo.md" "$WORK/restore-foo.md"
  cp "$WORK/cand.md" "$WORK/agents/foo.md"

  [ "$(cat "$WORK/agents/foo.md")" = "CANDIDATE" ]

  # restore
  mv "$WORK/restore-foo.md" "$WORK/agents/foo.md"
  [ "$(cat "$WORK/agents/foo.md")" = "ORIGINAL" ]

  rm -rf "$WORK"
}
