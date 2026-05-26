---
description: research 세션을 LLM 위키(wiki/)로 합성·상호링크하고 Quartz로 발행. ingest|query|lint|publish.
argument-hint: "<ingest <slug|--all|--new> | query \"질문\" | lint [--fix] | publish [--deploy]>"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

## Inputs
`$ARGUMENTS` — 첫 토큰 = action (ingest|query|lint|publish), 나머지 = 인자.

## Constants
- `${CLAUDE_PLUGIN_ROOT}` = 플러그인 루트.
- `VAULT` = `<project_cwd>/wiki`, `RESEARCH_DIR` = `<project_cwd>/research`
- Date today: !`date -u +%Y-%m-%d`

## 부트스트랩 (모든 액션 공통)
```
mkdir -p "${VAULT}/concepts" "${VAULT}/entities" "${VAULT}/_index"
[ -f "${VAULT}/AGENTS.md" ] || cp "${CLAUDE_PLUGIN_ROOT}/lib/wiki/AGENTS.template.md" "${VAULT}/AGENTS.md"
[ -f "${VAULT}/index.md" ] || printf '# Wiki Index\n' > "${VAULT}/index.md"
```

## Action: ingest
인자: `<slug>` | `--all` | `--new` (`--all --rebuild` = 해당 소스 섹션 강제 교체).

### 단일 slug 절차 (링크를 apply 전에 확정 — 단일 apply)
1. `wiki/log.md`를 읽어 **정확매칭**으로 이미 인제스트된 소스면 알리고 중단(중복 방지). 단 `--rebuild`(및 명시적 단일 재처리)는 이 중단을 건너뛴다.
2. `research/<slug>/README.md` + `sources.json`을 읽는다. **raw 수정 금지.**
3. `wiki/index.md`(기존 페이지 카탈로그)와 `wiki/AGENTS.md`(헌법)를 읽는다.
4. 헌법 규칙대로 엔티티·개념을 추출해 각 page에:
   - `type, title, slug`(slugify 규칙: ASCII), `aliases`, `sources`(반드시 `research/<slug>` 포함), `confidence`.
   - `tldr`(신규 시 한 줄), `perspective`(이 세션 관점, 각 주장에 그 세션 `sources.json`의 `[n]` 인용).
   - `links` (producer 규칙): LLM은 **index.md 카탈로그 실재 페이지** 또는 **이번 pagePlan 형제 slug**만 고른다(진짜 개념적 연결만, 표면 겹침 배제). — apply 관용: apply는 미존재 링크도 거부하지 않고 soft-link로 보존하며 lint가 broken-link로 표시.
5. pagePlan JSON(위 계약)을 `wiki/_index/plan-<slug>.json`에 쓴다.
6. **단일 apply**:
   ```
   node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/apply.mjs" --vault "${VAULT}" --plan "${VAULT}/_index/plan-<slug>.json" --date <today>
   ```
7. 결과(JSON: created/merged/source)를 한글 2줄로 보고.

### --all / --new
- 두 경우 모두 `research/`의 세션을 순회하되, `log.md`에 **정확매칭**으로 있는 소스는 skip(재개 가능).
- 차이: `--new`는 신규만(정의상 동일 skip). `--all`은 전체 순회이며, `--all --rebuild`일 때만 이미 처리된 소스도 다시 처리(해당 `### research/<slug>` 섹션 교체 — apply의 perspective upsert가 같은 키를 덮어씀).
- 일괄 종료 후 `lint`를 1회 실행해 요약 보고.

## Action: query
(Task 9)

## Action: lint
(Task 8)

## Action: publish
(Task 10)
