#!/usr/bin/env bats
#
# Regression tests for push_to_notion.sh covering the two failure modes
# discovered on 2026-04-18:
#
#   RC#2  select-schema mismatch — Notion API rejected the row because
#         audience_level contained a comma and purpose was free-form
#         Korean that didn't match any of the database's select options.
#
#   RC#3  MAX_ARG_STRLEN (131072 B per argv entry) — once README + a long
#         transcript + 20+ related/*.md accumulated into BODY_BLOCKS, the
#         final `jq --argjson b "$BODY_BLOCKS" ...` call failed with
#         "Argument list too long".
#
# All tests use DRY_RUN=1 so they never call the Notion API.

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/push_to_notion.sh"

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR}"
  export WORK="$TMPDIR/session"
  mkdir -p "$WORK/cache" "$WORK/related"
  cat > "$WORK/README.md" <<'EOF'
---
title: "fixture session"
slug: "fixture"
created: "2026-04-18"
input_type: "topic"
---

# Body
Some content.
EOF
  cat > "$WORK/sources.json" <<'EOF'
{ "input": "fixture", "input_type": "topic", "created": "2026-04-18", "sources": [] }
EOF
  # Required env
  export NOTION_TOKEN="dry-token"
  export NOTION_PARENT_PAGE_ID="dry-parent"
  export NOTION_DATABASE_ID="dry-db"
  export DRY_RUN=1
}

# ---------- RC#2 — select enum validation ----------

@test "RC#2: invalid purpose/audience (with comma) is omitted, not sent" {
  cat > "$WORK/intent.json" <<'EOF'
{
  "purpose": "구매 검토 (purchase decision)",
  "audience_level": "캠핑 경험자, 프리미엄 텐트 구매 검토 중"
}
EOF
  WORK_RENAMED="$TMPDIR/2026-04-18-fixture"
  mv "$WORK" "$WORK_RENAMED"
  run bash "$SCRIPT" "$WORK_RENAMED"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "warn: purpose=" || { echo "expected purpose warning, got: $output" >&2; return 1; }
  echo "$output" | grep -q "warn: audience=" || { echo "expected audience warning, got: $output" >&2; return 1; }
}

@test "RC#2: valid enum purpose/audience emit select properties" {
  cat > "$WORK/intent.json" <<'EOF'
{ "purpose": "의사결정", "audience_level": "중급" }
EOF
  WORK_RENAMED="$TMPDIR/2026-04-18-fixture"
  mv "$WORK" "$WORK_RENAMED"
  run bash "$SCRIPT" "$WORK_RENAMED"
  [ "$status" -eq 0 ]
  # No enum warnings for valid values
  ! echo "$output" | grep -q "warn: purpose=" || { echo "unexpected warning for valid purpose" >&2; return 1; }
  ! echo "$output" | grep -q "warn: audience=" || { echo "unexpected warning for valid audience" >&2; return 1; }
}

@test "RC#2: non-enum input_type is omitted" {
  cat > "$WORK/sources.json" <<'EOF'
{ "input": "x", "input_type": "some-weird-thing", "created": "2026-04-18", "sources": [] }
EOF
  WORK_RENAMED="$TMPDIR/2026-04-18-fixture"
  mv "$WORK" "$WORK_RENAMED"
  run bash "$SCRIPT" "$WORK_RENAMED"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "warn: input_type=" || { echo "expected input_type warning, got: $output" >&2; return 1; }
}

# ---------- RC#3 — MAX_ARG_STRLEN ----------

# Build a report dir whose README + transcript + 40 related/*.md combined
# produce a BODY_BLOCKS JSON blob that would exceed a 131KB --argjson on
# the old code path. If the fix regresses, jq will abort with
# "Argument list too long" and bash will exit non-zero.
@test "RC#3: large README + transcript + 40 related files do not exceed argv" {
  # Pad README to ~40KB
  {
    echo "---"
    echo 'title: "big session"'
    echo 'slug: "big"'
    echo "---"
    echo
    for i in $(seq 1 500); do
      echo "- point $i $(printf 'lorem ipsum dolor sit amet %.0s' {1..10})"
    done
  } > "$WORK/README.md"

  # Transcript ~80KB, well past MAX_ARG_STRLEN on its own
  {
    for i in $(seq 1 1200); do
      echo "### window $i (00:00–02:00)"
      echo "$(printf 'transcript paragraph chunk %.0s' {1..10})"
      echo
    done
  } > "$WORK/transcript.md"

  # 40 related files, each ~2KB, together another ~80KB after JSON expansion
  for i in $(seq 1 40); do
    {
      echo "# related item $i"
      echo
      echo "$(printf 'short description line $i %.0s' {1..15})"
      echo
      echo "- https://example.com/$i"
    } > "$WORK/related/competitor-$i.md"
  done

  WORK_RENAMED="$TMPDIR/2026-04-18-big"
  mv "$WORK" "$WORK_RENAMED"
  run bash "$SCRIPT" "$WORK_RENAMED"
  [ "$status" -eq 0 ]
  # Must have reached the block-write stage (proves BODY_BLOCKS was assembled)
  echo "$output" | grep -q "wrote .* top-level blocks" || {
    echo "expected block-write log, got: $output" >&2
    return 1
  }
  # And must NOT contain the old argv error
  ! echo "$output" | grep -q "Argument list too long" || {
    echo "regression: argv limit hit: $output" >&2
    return 1
  }
}
