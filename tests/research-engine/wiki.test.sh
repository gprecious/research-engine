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

@test "wiki command bootstrap: Obsidian vault 이름 해석 + tagged apply" {
  grep -q 'vault_resolve.mjs' "${REPO_ROOT}/commands/wiki.md"

  OBS_HOME="${TMP}/home"
  HARRY="${TMP}/harry"
  mkdir -p "${OBS_HOME}/Library/Application Support/obsidian" "${HARRY}" "${TMP}/research/2026-04-27-moe"
  cat > "${OBS_HOME}/Library/Application Support/obsidian/obsidian.json" <<EOF
{"vaults":{"a":{"path":"${HARRY}","open":true,"ts":200}}}
EOF
  cat > "${TMP}/research/2026-04-27-moe/README.md" <<'EOF'
# MoE
라우터가 토큰을 일부 전문가에게만 보낸다. [1]
EOF
  cat > "${TMP}/research/2026-04-27-moe/sources.json" <<'EOF'
[{"id":1,"title":"Fixture"}]
EOF

  run bash -c '
    set -euo pipefail
    export CLAUDE_PLUGIN_ROOT="$1"
    export HOME="$2"
    export LLM_OBSIDIAN_VAULT_NAME=harry
    VAULT="$(node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/vault_resolve.mjs")"
    mkdir -p "${VAULT}/concepts" "${VAULT}/entities" "${VAULT}/synthesis" "${VAULT}/ephemeral" "${VAULT}/_drafts" "${VAULT}/_todos" "${VAULT}/_index"
    [ -f "${VAULT}/AGENTS.md" ] || cp "${CLAUDE_PLUGIN_ROOT}/lib/wiki/AGENTS.template.md" "${VAULT}/AGENTS.md"
    [ -f "${VAULT}/index.md" ] || printf "# Wiki Index\n" > "${VAULT}/index.md"
    cp "$3" "${VAULT}/_index/plan-moe.json"
    node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/vault_resolve.mjs" --explain > "${VAULT}/_index/vault-explain.json"
    node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/apply.mjs" --vault "${VAULT}" --plan "${VAULT}/_index/plan-moe.json" --date 2026-05-25
  ' _ "${REPO_ROOT}" "${OBS_HOME}" "${FIXTURE}"
  [ "$status" -eq 0 ]
  [ -f "${HARRY}/LLM-Wiki/concepts/mixture-of-experts.md" ]
  grep -q 'ai-generated' "${HARRY}/LLM-Wiki/concepts/mixture-of-experts.md"
  grep -q '"mode": "name"' "${HARRY}/LLM-Wiki/_index/vault-explain.json"
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

@test "librarian CLI: safe apply + draft 격리 + report" {
  grep -q 'Action: librarian' "${REPO_ROOT}/commands/wiki.md"

  mkdir -p "${VAULT}/concepts" "${VAULT}/_index"
  cat > "${VAULT}/concepts/a.md" <<'EOF'
---
type: concept
title: A
slug: a
sources:
  - research/a
related:
  - "[[ghost]]"
created: 2026-01-01
updated: 2026-01-01
---

## 출처별 관점
### research/a
- 주장 [1]

## 관련 개념

- [[ghost]]
EOF
  cat > "${VAULT}/_index/librarian-plan.json" <<'EOF'
{
  "draft": [
    {
      "rule": "new-page",
      "pagePlan": {
        "source": "research/a",
        "pages": [
          {
            "type": "synthesis",
            "title": "Synth",
            "slug": "synth",
            "aliases": [],
            "sources": ["research/a"],
            "confidence": "medium",
            "tldr": "요약",
            "perspective": "- 합성 [1].",
            "links": []
          }
        ]
      }
    }
  ]
}
EOF

  run node "${REPO_ROOT}/lib/wiki/librarian.mjs" --vault "${VAULT}" --apply --budget 50 --date 2026-06-09
  [ "$status" -eq 0 ]
  grep -q 'status: stale' "${VAULT}/concepts/a.md"
  grep -q 'ai-generated' "${VAULT}/concepts/a.md"
  ! grep -q '\[\[ghost\]\]' "${VAULT}/concepts/a.md"
  grep -q 'broken-link' "${VAULT}/change_log.md"
  grep -q 'stale-flag' "${VAULT}/change_log.md"
  grep -q 'new-page' "${VAULT}/outputs/librarian-2026-06-09.md"
  [ -f "${VAULT}/_drafts/synthesis/synth.md" ]
}

@test "promote CLI: draft → live + index 갱신 + 멱등" {
  grep -q 'Action: promote' "${REPO_ROOT}/commands/wiki.md"

  mkdir -p "${VAULT}/_drafts/concepts"
  cat > "${VAULT}/_drafts/concepts/draft-a.md" <<'EOF'
---
type: concept
title: Draft A
slug: draft-a
aliases: []
sources:
  - research/a
related: []
tags:
  - ai-generated
  - llm-wiki
  - concept
confidence: medium
created: 2026-06-08
updated: 2026-06-08
---

## TL;DR
요약

## 출처별 관점

### research/a
- 주장 [1]
EOF

  run node "${REPO_ROOT}/lib/wiki/promote.mjs" --vault "${VAULT}" --all --date 2026-06-09
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.promoted == ["concepts/draft-a.md"]'
  [ -f "${VAULT}/concepts/draft-a.md" ]
  [ ! -f "${VAULT}/_drafts/concepts/draft-a.md" ]
  grep -q '\[\[draft-a\]\]' "${VAULT}/index.md"

  run node "${REPO_ROOT}/lib/wiki/promote.mjs" --vault "${VAULT}" --slug draft-a --date 2026-06-09
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.promoted == []'
  echo "$output" | jq -e '.skipped[0].reason == "already-live"'
}

@test "publish: Quartz 미설치면 설치 안내 후 비정상 종료" {
  QUARTZ_DIR="${TMP}/no-quartz" VAULT="${VAULT}" run bash "${REPO_ROOT}/scripts/wiki_publish.sh"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Quartz 미설치"
}
