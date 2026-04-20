#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/patch_readme.sh"

setup() {
  TMPDIR_T="$(mktemp -d)"
  README="$TMPDIR_T/README.md"
  BLOCK="$TMPDIR_T/block.md"
  cat > "$BLOCK" <<'EOF'
## 시각 자료

![chart](figures/chart-01-x.png)
EOF
}

teardown() { rm -rf "$TMPDIR_T"; }

@test "appends before ## Sources when markers absent" {
  cat > "$README" <<'EOF'
# Title

body

## Sources

1. foo
EOF
  run "$SCRIPT" "$README" "$BLOCK"
  [ "$status" -eq 0 ]
  run grep -c '<!-- viz:begin -->' "$README"
  [ "$output" = "1" ]
  run grep -c '<!-- viz:end -->' "$README"
  [ "$output" = "1" ]
  # viz block must precede Sources
  python3 - "$README" <<'PY'
import sys
text = open(sys.argv[1]).read()
b = text.index('<!-- viz:begin -->')
s = text.index('## Sources')
assert b < s, f"viz block not before Sources: {b} >= {s}"
PY
}

@test "appends at end when no ## Sources section exists" {
  cat > "$README" <<'EOF'
# Title

just body, no sources
EOF
  run "$SCRIPT" "$README" "$BLOCK"
  [ "$status" -eq 0 ]
  run tail -n1 "$README"
  [ "$output" = "<!-- viz:end -->" ]
}

@test "replaces in-place when markers present" {
  cat > "$README" <<'EOF'
# Title

<!-- viz:begin -->
## 시각 자료 OLD
OLD BODY
<!-- viz:end -->

## Sources

1. foo
EOF
  run "$SCRIPT" "$README" "$BLOCK"
  [ "$status" -eq 0 ]
  ! grep -q 'OLD BODY' "$README"
  grep -q 'chart-01-x.png' "$README"
  # exactly one pair of markers
  [ "$(grep -c '<!-- viz:begin -->' "$README")" = "1" ]
  [ "$(grep -c '<!-- viz:end -->' "$README")" = "1" ]
}

@test "idempotent: running twice produces identical file" {
  cat > "$README" <<'EOF'
# Title

body

## Sources

1. foo
EOF
  "$SCRIPT" "$README" "$BLOCK"
  cp "$README" "$TMPDIR_T/after1.md"
  "$SCRIPT" "$README" "$BLOCK"
  run diff "$TMPDIR_T/after1.md" "$README"
  [ "$status" -eq 0 ]
}

@test "does not modify non-marker text" {
  cat > "$README" <<'EOF'
# Title

body line A
body line B

<!-- viz:begin -->
old block
<!-- viz:end -->

tail line
EOF
  "$SCRIPT" "$README" "$BLOCK"
  grep -q 'body line A' "$README"
  grep -q 'body line B' "$README"
  grep -q 'tail line' "$README"
}

@test "fails when README missing" {
  run "$SCRIPT" "$TMPDIR_T/ghost.md" "$BLOCK"
  [ "$status" -ne 0 ]
}

@test "fails when block file missing" {
  cat > "$README" <<< "# t"
  run "$SCRIPT" "$README" "$TMPDIR_T/ghost.md"
  [ "$status" -ne 0 ]
}
