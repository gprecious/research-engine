#!/usr/bin/env bats

setup() {
  export PATH="$(pwd)/tests/research-design/mock-bin:$PATH"
  export RESEARCH_DESIGN_MOCK=1
  export RESEARCH_DESIGN_JUDGE_MOCK=1
}

@test "pipeline script exists and is executable" {
  [ -x scripts/research_design_pipeline.sh ]
}

@test "pipeline rejects missing slug" {
  run scripts/research_design_pipeline.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"slug required"* ]]
}

@test "pipeline rejects non-existent slug" {
  run scripts/research_design_pipeline.sh "nope-doesnt-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
}

@test "pipeline mock run produces design/runs/<iso>/log.jsonl for seed slug" {
  run scripts/research_design_pipeline.sh "2026-05-22-ai-image-vectorization-service"
  [ "$status" -eq 0 ]
  ls research/2026-05-22-ai-image-vectorization-service/design/runs/ | grep -q '^[0-9]'
}
