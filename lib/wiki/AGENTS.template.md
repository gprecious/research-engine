# wiki/AGENTS.md — LLM Wiki 헌법

이 vault를 ingest/lint 하는 에이전트는 아래 규칙을 반드시 따른다.

## 계층
- `../research/` = raw 불변 소스. **절대 수정하지 않는다.** 읽기 전용.
- `concepts/`, `entities/` = 이 위키가 생성하는 atemporal 합성 페이지.
- `synthesis/` = dream 전용 cross-wiki 페이지. 반드시 2개 이상 소스 페이지 근거를 명시한다.
- `ephemeral/` = 세션성·TTL 지식. frontmatter `expires`가 있으면 만료 후보로 본다.
- `_drafts/` = 미승인 산출 대기소. query/publish/index 대상에서 제외한다.
- `index.md` = 카탈로그(재생성). 링크 선택의 근거. `log.md` = append-only 인제스트 원장(소스당 1줄).

## 페이지 규칙
1. 1 페이지 = 1 개념(concept), 1 엔티티(entity: 인물·조직·모델·논문·도구), synthesis 또는 ephemeral. raw 절대 수정 금지.
2. **slug = ASCII kebab-case** (`^[a-z0-9]+(-[a-z0-9]+)*$`). 한글은 title·aliases 에만. 영문 개념명을 slug 로.
3. frontmatter 필수: `type, title, slug, sources, related, tags, created, updated`. 선택: `aliases, confidence, expires`.
4. `tags` 는 기존 태그를 보존하고 항상 `ai-generated`, `llm-wiki`, `<type>` 을 포함한다.
5. **모든 사실 주장은 `## 출처별 관점`의 `### research/<slug>` 섹션 안에서 그 세션의 `[n]`으로 인용**한다(세션-로컬 번호). 무출처 주장 금지.
6. 링크 신뢰원 = frontmatter `related`. 본문 `## 관련 개념`은 related 에서 렌더링된다(직접 편집·중복 금지).
7. 링크는 `index.md` 카탈로그에 **실재하는 페이지**와의 진짜 개념적 연결만. 표면 키워드 겹침으로 링크하지 않는다.
8. 신규 페이지, 새 related 링크, synthesis, evolve 산출은 먼저 `_drafts/` 에 쓴다. promote 전에는 live index/graph에 올리지 않는다.

## 본문 구조
## TL;DR
<한 줄>

## 출처별 관점
### research/<slug>
- 주장 ... [1]

## 관련 개념   ← related 에서 자동 렌더링
- [[other-slug]]

## 연산
- ingest: 소스 + index.md 카탈로그 읽기 → pagePlan(JSON, links 포함) 생성 → apply 1회.
- query: 위키 페이지에서 인용과 함께 합성. raw 재독 금지.
- lint: 무출처·미해결인용·끊긴링크·고아·중복 보고.

## 문체
- AI가 쓴 듯한 포괄적 칭찬, 근거 없는 확신, 빈 요약 문장을 피한다. 출처가 말한 구체 주장과 한계를 짧게 쓴다.
