#!/usr/bin/env bats

setup() {
  export PATH="$(pwd)/tests/research-engine/mock-bin:$PATH"
  export RESEARCH_ENGINE_DEPLOY_MOCK=1
  SLUG="2026-05-23-deploy-test-fixture"
  TARGET="research/${SLUG}"
  mkdir -p "${TARGET}/spec" "${TARGET}/app"
  echo "# Test" > "${TARGET}/README.md"
  cp tests/research-engine/fixtures/scenarios-valid.json "${TARGET}/spec/scenarios.json"
  cp tests/research-engine/fixtures/app-sample/package.json "${TARGET}/app/package.json"
  export HETZNER_MASTER_HOST=mock-host
  export HETZNER_MASTER_USER=mock-user
}

teardown() {
  rm -rf "research/2026-05-23-deploy-test-fixture"
}

@test "deploy dispatch exists and is executable" {
  [ -x scripts/deploy_dispatch.sh ]
}

@test "deploy rejects missing slug" {
  run scripts/deploy_dispatch.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"slug required"* ]]
}

@test "deploy rejects missing app/" {
  rm -rf "research/2026-05-23-deploy-test-fixture/app"
  run scripts/deploy_dispatch.sh "2026-05-23-deploy-test-fixture"
  [ "$status" -ne 0 ]
  [[ "$output" == *"app"* ]]
}

@test "deploy in mock mode produces deploy.json with mock host" {
  run scripts/deploy_dispatch.sh "2026-05-23-deploy-test-fixture"
  [ "$status" -eq 0 ]
  [ -f "research/2026-05-23-deploy-test-fixture/deploy/deploy.json" ]
  jq -e '.target == "lxc"' "research/2026-05-23-deploy-test-fixture/deploy/deploy.json"
  jq -e '.host | length > 0' "research/2026-05-23-deploy-test-fixture/deploy/deploy.json"
}

@test "deploy writes runs/<ISO>/log.jsonl with stage=deploy" {
  scripts/deploy_dispatch.sh "2026-05-23-deploy-test-fixture"
  RUN=$(ls research/2026-05-23-deploy-test-fixture/deploy/runs/ | head -1)
  [ -n "${RUN}" ]
  grep -q '"stage":"deploy"' "research/2026-05-23-deploy-test-fixture/deploy/runs/${RUN}/log.jsonl"
}
