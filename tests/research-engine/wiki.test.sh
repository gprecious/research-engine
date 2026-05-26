#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  FIXTURE="${REPO_ROOT}/tests/research-engine/fixtures/wiki/plan-moe.json"
  TMP="$(mktemp -d)"; VAULT="${TMP}/wiki"
  mkdir -p "${VAULT}/concepts" "${VAULT}/entities" "${VAULT}/_index"
  export REPO_ROOT FIXTURE VAULT TMP
}
teardown() { rm -rf "${TMP}"; }

@test "apply CLI: pagePlan → 페이지·index·log 생성" {
  run node "${REPO_ROOT}/lib/wiki/apply.mjs" --vault "${VAULT}" --plan "${FIXTURE}" --date 2026-05-25
  [ "$status" -eq 0 ]
  [ -f "${VAULT}/concepts/mixture-of-experts.md" ]
  [ -f "${VAULT}/entities/transformer.md" ]
  grep -q "\[\[mixture-of-experts\]\]" "${VAULT}/index.md"
  [ "$(grep -c 'ingest | research/2026-04-27-moe' "${VAULT}/log.md")" -eq 1 ]
}

@test "apply CLI: 같은 소스 두 번 = 멱등(섹션·log 무중복)" {
  node "${REPO_ROOT}/lib/wiki/apply.mjs" --vault "${VAULT}" --plan "${FIXTURE}" --date 2026-05-25
  node "${REPO_ROOT}/lib/wiki/apply.mjs" --vault "${VAULT}" --plan "${FIXTURE}" --date 2026-05-26
  [ "$(grep -c '### research/2026-04-27-moe' "${VAULT}/concepts/mixture-of-experts.md")" -eq 1 ]
  [ "$(grep -c 'ingest |' "${VAULT}/log.md")" -eq 1 ]
}

@test "lint CLI: 끊긴 링크·무출처 탐지" {
  mkdir -p "${VAULT}/concepts"
  cat > "${VAULT}/concepts/a.md" <<'EOF'
---
type: concept
title: A
slug: a
sources: []
related:
  - "[[ghost]]"
created: 2026-05-25
updated: 2026-05-25
---

## 출처별 관점
무출처 본문 주장
EOF
  run node "${REPO_ROOT}/lib/wiki/lint.mjs" --vault "${VAULT}"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.findings[] | select(.rule=="broken-link" and .slug=="a")'
  echo "$output" | jq -e '.findings[] | select(.rule=="unsourced" and .slug=="a")'
}
