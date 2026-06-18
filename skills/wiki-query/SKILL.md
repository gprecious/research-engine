---
name: wiki-query
description: Use when an agent needs background or prior findings on a topic that may already be researched — look it up in the LLM-Wiki (the Obsidian vault built by research-engine) instead of re-researching. Searches distilled concepts/entities and verbatim reports, returns a cited answer, never edits the vault. Triggers on "위키 찾아봐", "이전 리서치 있어?", "wiki lookup", "what do we already know about X", needing context already captured by /research.
---

# LLM-Wiki Query

read-only 가이드. 이 vault 를 **쓰지 않는다**(작성은 `/wiki ingest`·`promote` 의 일). 이미 연구된 지식을 빠르게 찾아 **인용과 함께** 답하는 절차만 제공한다.

## 1. Vault 경로 해석

```bash
VAULT="$(node "${CLAUDE_PLUGIN_ROOT:-.}/lib/wiki/vault_resolve.mjs")"
node "${CLAUDE_PLUGIN_ROOT:-.}/lib/wiki/vault_resolve.mjs" --explain   # ok / mode 확인
```

- 우선순위: `WIKI_VAULT`(명시 경로) > `LLM_OBSIDIAN_VAULT_NAME`(+`LLM_WIKI_SUBDIR`, 기본 `LLM-Wiki`) > 기본 `<cwd>/wiki`.
- `--explain` 의 `"ok": false` 면 vault 미설정 — 조회 불가. 사용자에게 vault 설정(`WIKI_VAULT` 또는 `LLM_OBSIDIAN_VAULT_NAME`)을 안내하고 중단.

## 2. Vault 구조 (무엇이 어디 있나)

| 경로 | 내용 | 조회 시 |
| --- | --- | --- |
| `concepts/` | atemporal 개념 합성 페이지 | 1순위 검색 |
| `entities/` | 인물·조직·모델·논문·도구 | 1순위 검색 |
| `synthesis/` | dream 전용 cross-wiki 페이지 | 보조 |
| `ephemeral/` | TTL 지식(`expires` 있으면 만료 후보) | 신선도 확인 |
| `reports/` | **research README 전문(verbatim)** — 세부 원문이 필요할 때 | 깊이 필요 시 |
| `index.md` | 전체 카탈로그(링크 근거) | 후보 선정에 먼저 훑기 |
| `log.md` | 인제스트 원장(소스당 1줄) | 어떤 세션이 들어왔는지 |
| `_drafts/` | 미승인 산출 | **조회 제외** |

distilled 페이지(`concepts/entities`)는 핵심 주장을 압축한 1순위, `reports/`는 같은 세션의 **전체 보고서 원문**(더 깊은 맥락·수치·인용 추적용).

## 3. 조회 절차 (임베딩 없음 — grep 기반)

1. 핵심어로 후보 찾기:
   ```bash
   grep -ril "<키워드>" "${VAULT}/concepts" "${VAULT}/entities" "${VAULT}/synthesis" 2>/dev/null
   ```
   + `${VAULT}/index.md` 카탈로그(한 줄 요약)를 훑어 관련 slug 보강. `_drafts/` 는 제외.
2. 후보 페이지를 읽고 **인용과 함께** 한국어로 합성 답변. 각 사실에 **출처 페이지 slug + 그 페이지의 `### research/<slug>` 인용**을 명시.
3. 더 깊은 원문·수치·맥락이 필요하면 `reports/` 에서 같은 주제의 verbatim 보고서를 grep 해 읽는다:
   ```bash
   grep -ril "<키워드>" "${VAULT}/reports" 2>/dev/null
   ```
   reports frontmatter 의 `report_slug`/`source` 로 어느 research 세션인지 추적 가능.
4. raw `research/<slug>/README.md` 재독은 **마지막 수단** — 위키가 source-of-truth. reports/ 가 이미 그 전문 사본이다.

## 4. 규칙

- **read-only.** 페이지를 수정/생성하지 않는다. 새 지식 반영은 `/wiki ingest`(자동) 또는 `/wiki promote`.
- 무출처 단정 금지 — 위키에 근거가 없으면 "위키에 없음"이라고 답하고 `/research <주제>` 를 제안.
- 필터 태그: `tag:#ai-generated`(전체), `tag:#research-report`(verbatim 보고서), `tag:#llm-wiki`(distilled 페이지).
- 한 질문이 여러 페이지·여러 세션을 합성할 수 있다. 상충되는 관점은 각 출처를 나란히 제시한다.

## 5. 슬래시 명령과의 관계

`/wiki query "<질문>"` 은 같은 grep-합성을 패키징한 Claude 슬래시 명령이다. 이 skill 은 **어떤 agent든** 흐름 중간에 배경지식이 필요할 때 직접 따르는 절차(특히 `reports/` 까지 포함)를 제공한다.
