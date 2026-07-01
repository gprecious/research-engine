#!/usr/bin/env bats

CMD="$BATS_TEST_DIRNAME/../../commands/research.md"

@test "research.md defines Stage 3.5 Lens Plan calling the lens gate" {
  grep -q "Stage 3.5 — Lens Plan" "$CMD"
  grep -q "lens_gate.sh" "$CMD"
  grep -q "lens_plan.json" "$CMD"
  grep -q "lens-planner" "$CMD"
}
@test "research.md documents the --lens / --no-lens flags" {
  grep -q -- "--lens" "$CMD"
  grep -q -- "--no-lens" "$CMD"
}
@test "Stage 4 dispatch injects lens_hints when a plan exists" {
  grep -q "lens_hints" "$CMD"
}
@test "research.md defines Stage 4.6 Claim Review calling the review gate" {
  grep -q "Stage 4.6 — Claim Review" "$CMD"
  grep -q "claim_review_gate.sh" "$CMD"
  grep -q "claim_review.json" "$CMD"
  grep -q "claim-reviewer" "$CMD"
}
@test "Stage 4.6 validates the artifact via the validator CLI" {
  grep -q "claim_review_validator.mjs" "$CMD"
}
@test "Stage 3.5 validates the artifact via the validator CLI" {
  grep -q "lens_plan_validator.mjs" "$CMD"
}

@test "report_sections.md documents the 검증 매트릭스 section" {
  SEC="$BATS_TEST_DIRNAME/../../lib/report_sections.md"
  grep -q "검증 매트릭스" "$SEC"
  grep -q "claim_review.json" "$SEC"
}
@test "report_sections.md documents the 누락 관점 / 후속 질문 section" {
  SEC="$BATS_TEST_DIRNAME/../../lib/report_sections.md"
  grep -q "누락 관점 / 후속 질문" "$SEC"
  grep -q "missing_lenses" "$SEC"
}
