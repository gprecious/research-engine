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
    # hermetic: 머신 env 의 명시 vault override 를 제거해 name-resolution 만 검증(실제 vault 오염 방지).
    unset WIKI_VAULT LLM_WIKI_SUBDIR
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

@test "dream --target=wiki deterministic outputs" {
  grep -q -- '--target=wiki' "${REPO_ROOT}/commands/dream.md"

  mkdir -p "${VAULT}/concepts" "${VAULT}/entities"
  cat > "${VAULT}/concepts/router.md" <<'EOF'
---
type: concept
title: Router
slug: router
aliases: []
sources: [research/a]
related: []
tags: [ai-generated, llm-wiki, concept]
confidence: medium
created: 2026-06-01
updated: 2026-06-01
---

## TL;DR
라우터 요약
EOF
  cat > "${VAULT}/entities/model-x.md" <<'EOF'
---
type: entity
title: Model X
slug: model-x
aliases: []
sources: [research/b]
related: []
tags: [ai-generated, llm-wiki, entity]
confidence: medium
created: 2026-06-01
updated: 2026-06-01
---

## TL;DR
모델 요약
EOF
  cat > "${TMP}/dream-wiki.json" <<'EOF'
{
  "synthesis": {
    "slug": "routing-constraints",
    "title": "Routing Constraints",
    "summary": "라우팅 제약은 반복된다.",
    "evidenceSlugs": ["router", "model-x"],
    "sources": ["research/a", "research/b"]
  },
  "todo": {
    "slug": "routing-gap",
    "title": "Routing Gap",
    "question": "라우팅 제약을 더 조사할까?"
  }
}
EOF
  run node "${REPO_ROOT}/lib/wiki/wiki_dream.mjs" --vault "${VAULT}" --apply "${TMP}/dream-wiki.json" --date 2026-06-09
  [ "$status" -eq 0 ]
  [ -f "${VAULT}/_drafts/synthesis/routing-constraints.md" ]
  grep -q 'type: synthesis' "${VAULT}/_drafts/synthesis/routing-constraints.md"
  grep -q 'ai-generated' "${VAULT}/_drafts/synthesis/routing-constraints.md"
  [ -f "${VAULT}/_todos/routing-gap.md" ]
  jq -e '.runs[0].synthesis == "routing-constraints"' "${VAULT}/_index/reflect_state.json"
}

@test "evolve wiki deterministic outputs and live AGENTS unchanged" {
  grep -q 'wiki evolvable region' "${REPO_ROOT}/commands/evolve.md"

  cat > "${VAULT}/AGENTS.md" <<'EOF'
# Wiki Constitution

<!-- evolvable:page-rules -->
old rules
<!-- /evolvable -->
EOF
  before="$(cat "${VAULT}/AGENTS.md")"
  cat > "${TMP}/mutator.json" <<'EOF'
{"variants":[{"body":"new rules","rationale":"test"}]}
EOF

  run node "${REPO_ROOT}/lib/wiki/wiki_evolve.mjs" --vault "${VAULT}" --apply-candidate "${TMP}/mutator.json" --region page-rules --date 2026-06-09
  [ "$status" -eq 0 ]
  [ -f "${VAULT}/_drafts/_schema/agents-page-rules.candidate.md" ]
  jq -e '.entries[0].region == "page-rules"' "${VAULT}/_index/evolve-ledger.json"
  [ "$(cat "${VAULT}/AGENTS.md")" = "${before}" ]
}

@test "publish: synthesis 포함, draft/todos/index/ephemeral 제외" {
  QUARTZ="${TMP}/quartz"
  FAKEBIN="${TMP}/bin"
  mkdir -p "${VAULT}/concepts" "${VAULT}/entities" "${VAULT}/synthesis" "${VAULT}/ephemeral" "${VAULT}/_drafts" "${VAULT}/_todos" "${VAULT}/_index" "${QUARTZ}" "${FAKEBIN}"
  printf '# Index\n' > "${VAULT}/index.md"
  printf '# Concept\n' > "${VAULT}/concepts/a.md"
  printf '# Entity\n' > "${VAULT}/entities/e.md"
  printf '# Synth\n' > "${VAULT}/synthesis/s.md"
  printf '# Ephemeral\n' > "${VAULT}/ephemeral/tmp.md"
  printf '# Draft\n' > "${VAULT}/_drafts/d.md"
  printf '# Todo\n' > "${VAULT}/_todos/t.md"
  printf '{}\n' > "${VAULT}/_index/state.json"
  cat > "${FAKEBIN}/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p public
printf '<html>ok</html>\n' > public/index.html
EOF
  chmod +x "${FAKEBIN}/npx"

  PATH="${FAKEBIN}:${PATH}" QUARTZ_DIR="${QUARTZ}" VAULT="${VAULT}" run bash "${REPO_ROOT}/scripts/wiki_publish.sh"
  [ "$status" -eq 0 ]
  [ -f "${QUARTZ}/content/concepts/a.md" ]
  [ -f "${QUARTZ}/content/entities/e.md" ]
  [ -f "${QUARTZ}/content/synthesis/s.md" ]
  [ ! -e "${QUARTZ}/content/_drafts" ]
  [ ! -e "${QUARTZ}/content/_todos" ]
  [ ! -e "${QUARTZ}/content/_index" ]
  [ ! -e "${QUARTZ}/content/ephemeral" ]
}

@test "wiki_librarian_cron: --dry-run echoes claude command" {
  run bash "${REPO_ROOT}/scripts/wiki_librarian_cron.sh" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'claude -p "/wiki librarian --apply --budget 50"'

  WIKI_LIBRARIAN_BUDGET=75 run bash "${REPO_ROOT}/scripts/wiki_librarian_cron.sh" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'claude -p "/wiki librarian --apply --budget 75"'
}

@test "publish: Quartz 미설치면 설치 안내 후 비정상 종료" {
  QUARTZ_DIR="${TMP}/no-quartz" VAULT="${VAULT}" run bash "${REPO_ROOT}/scripts/wiki_publish.sh"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Quartz 미설치"
}
