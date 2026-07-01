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

@test "claim-reviewer agent exists with name frontmatter" {
  grep -q "^name: claim-reviewer" "$AGENTS/claim-reviewer.md"
}
@test "claim-reviewer declares both evolvable regions" {
  grep -q "evolvable:contradiction-detection" "$AGENTS/claim-reviewer.md"
  grep -q "evolvable:missing-lens-detection" "$AGENTS/claim-reviewer.md"
}
@test "claim-reviewer references claim_review output contract" {
  grep -q "claim_review" "$AGENTS/claim-reviewer.md"
  grep -q "citation_status" "$AGENTS/claim-reviewer.md"
  grep -q "missing_lenses" "$AGENTS/claim-reviewer.md"
}
