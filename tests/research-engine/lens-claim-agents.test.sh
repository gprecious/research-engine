#!/usr/bin/env bats

AGENTS="$BATS_TEST_DIRNAME/../../agents"

@test "lens-planner agent exists with name frontmatter" {
  grep -q "^name: lens-planner" "$AGENTS/lens-planner.md"
}
@test "lens-planner declares both evolvable regions" {
  grep -q "evolvable:lens-selection" "$AGENTS/lens-planner.md"
  grep -q "evolvable:question-generation" "$AGENTS/lens-planner.md"
}
@test "lens-planner references lens_plan output contract" {
  grep -q "lens_plan" "$AGENTS/lens-planner.md"
  grep -q "generated" "$AGENTS/lens-planner.md"
}
