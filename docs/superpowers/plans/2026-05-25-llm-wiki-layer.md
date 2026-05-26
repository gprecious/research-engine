# LLM Wiki 레이어 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** research-engine의 raw 리서치 세션(`research/`)을 LLM이 합성·상호링크한 위키(`wiki/`)로 만들고 Quartz로 발행하는 `/wiki ingest|query|lint|publish` 명령군을 추가한다.

**Architecture:** 비결정 작업(엔티티/개념 추출·링크 선택·답변 합성)은 LLM(슬래시 명령 본문)이 수행하고, 그 출력(pagePlan JSON)을 **결정적 `lib/wiki/` 모듈**(frontmatter 스키마·원자 apply·lint)이 적용한다. 링크는 **`index.md` 카탈로그를 LLM에 제공해 직접 선택**(임베딩 없음 — claude+codex 교차리뷰 권고). apply는 **단일 실행**: 검증-전체 → 쓰기-전체 → log-1회. merge는 본문을 무한 append하지 않고 `### research/<slug>` 섹션 단위로 upsert하며, 링크 신뢰원은 frontmatter `related` 하나다.

**Tech Stack:** Node ESM(`.mjs`) · vitest(단위) · bats(명령/스크립트 계약) · `yaml`(frontmatter) · Quartz(정적 발행). 런타임 임베딩 의존성 없음. 기존 `${CLAUDE_PLUGIN_ROOT}` 글루·`commands/*.md` 컨벤션 준수.

**Spec:** `docs/superpowers/specs/2026-05-25-llm-wiki-layer-design.md` (claude+codex 교차리뷰 반영 개정판)

---

## File Structure

신규(플러그인에 ship):
- `lib/wiki/slug.mjs` — 제목→ASCII kebab slug(비ASCII는 해시 fallback)
- `lib/wiki/frontmatter.mjs` — 페이지 frontmatter 파싱/직렬화/검증(slug ASCII regex)
- `lib/wiki/index_log.mjs` — `index.md` 재생성, `log.md` append, **정확 라인매칭** ingest 판정
- `lib/wiki/apply.mjs` (+ CLI) — pagePlan→ **원자·단일** apply(검증-전체→쓰기-전체→log-1회, 섹션 merge, related 렌더링)
- `lib/wiki/lint.mjs` (+ CLI) — 무출처·미해결인용·끊긴링크·고아·중복(title/alias)
- `lib/wiki/AGENTS.template.md` — `wiki/AGENTS.md` 헌법 템플릿
- `scripts/wiki_publish.sh` — Quartz 빌드(+smoke)+배포 글루(QUARTZ_DIR = vault 밖, rsync 배포)
- `commands/wiki.md` — `/wiki <action>` 슬래시 명령

신규(콘텐츠/테스트):
- `tests/research-engine/wiki.test.sh` — bats 계약
- `tests/research-engine/fixtures/wiki/plan-moe.json` — pagePlan 픽스처
- `lib/wiki/*.test.mjs` — vitest 단위

수정:
- `.gitignore` — `wiki/` 추가
- `package.json` — `yaml` 의존성, `test:bats`에 wiki 타깃
- `skills/research-engine/SKILL.md` — 위키 워크플로(Codex 패리티)
- `.claude-plugin/plugin.json` — 버전 bump

페이지 위치: `wiki/concepts/<slug>.md`, `wiki/entities/<slug>.md`.

**pagePlan JSON 계약** (LLM 산출 → `apply.mjs` 소비):
```json
{
  "source": "research/2026-04-27-moe-llm-routing-improvements-2025",
  "pages": [
    {
      "type": "concept",
      "title": "Mixture of Experts",
      "slug": "mixture-of-experts",
      "aliases": ["MoE", "전문가 혼합"],
      "sources": ["research/2026-04-27-moe-llm-routing-improvements-2025"],
      "confidence": "high",
      "tldr": "라우터가 토큰을 일부 전문가에게만 보내 연산을 아끼는 구조.",
      "perspective": "- 라우터가 top-k 전문가를 고른다 [1].\n- 로드 밸런싱이 핵심 난제 [2].",
      "links": ["attention-mechanism", "transformer"]
    }
  ]
}
```
- `tldr`: 개념 한 줄 요약(신규 페이지에서만 본문 TL;DR로; merge 시 기존 TL;DR 유지).
- `perspective`: 이 소스 세션 관점. `### <source>` 섹션 본문이 된다. 인용 `[n]`은 그 세션 `sources.json`의 n번(세션-로컬 → merge에도 안정).
- `links`: `index.md` 카탈로그에서 LLM이 고른 실재 페이지 slug. apply 전에 확정.

---

## Phase 1 — Foundation

### Task 1: 디렉토리·의존성·헌법 템플릿·gitignore

**Files:**
- Modify: `.gitignore`, `package.json`
- Create: `lib/wiki/AGENTS.template.md`

- [ ] **Step 1: gitignore에 wiki 콘텐츠 추가**

`.gitignore`의 `# research outputs ...` 블록 아래에 추가:
```gitignore
# llm-wiki content (개인 지식 — 플러그인 배포 제외, 발행은 wiki/ 자체 git repo로)
wiki/
```

- [ ] **Step 2: 의존성 추가 (yaml 만 — 임베딩 의존성 없음)**

Run:
```bash
cd /home/taejin/projects/research-engine
npm pkg set dependencies.yaml="^2.4.5"
npm install
```
Expected: `node_modules/yaml` 설치. (`@huggingface/transformers`는 추가하지 않는다 — 카탈로그 직접 링크로 전환.)

- [ ] **Step 3: 헌법 템플릿 작성**

Create `lib/wiki/AGENTS.template.md`:
```markdown
# wiki/AGENTS.md — LLM Wiki 헌법

이 vault를 ingest/lint 하는 에이전트는 아래 규칙을 반드시 따른다.

## 계층
- `../research/` = raw 불변 소스. **절대 수정하지 않는다.** 읽기 전용.
- `concepts/`, `entities/` = 이 위키가 생성하는 합성 페이지.
- `index.md` = 카탈로그(재생성). 링크 선택의 근거. `log.md` = append-only 인제스트 원장(소스당 1줄).

## 페이지 규칙
1. 1 페이지 = 1 개념(concept) 또는 1 엔티티(entity: 인물·조직·모델·논문·도구). raw 절대 수정 금지.
2. **slug = ASCII kebab-case** (`^[a-z0-9]+(-[a-z0-9]+)*$`). 한글은 title·aliases 에만. 영문 개념명을 slug 로.
3. frontmatter 필수: `type, title, slug, sources, related, created, updated`. 선택: `aliases, confidence`.
4. **모든 사실 주장은 `## 출처별 관점`의 `### research/<slug>` 섹션 안에서 그 세션의 `[n]`으로 인용**한다(세션-로컬 번호). 무출처 주장 금지.
5. 링크 신뢰원 = frontmatter `related`. 본문 `## 관련 개념`은 related 에서 렌더링된다(직접 편집·중복 금지).
6. 링크는 `index.md` 카탈로그에 **실재하는 페이지**와의 진짜 개념적 연결만. 표면 키워드 겹침으로 링크하지 않는다.

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
```

- [ ] **Step 4: Commit**

```bash
git add .gitignore package.json package-lock.json lib/wiki/AGENTS.template.md
git commit -m "feat(wiki): 디렉토리 정책·yaml 의존성·헌법 템플릿"
```

---

### Task 2: `lib/wiki/slug.mjs` — ASCII slug 정규화(+해시 fallback)

**Files:** Create `lib/wiki/slug.mjs`, Test `lib/wiki/slug.test.mjs`

- [ ] **Step 1: 실패 테스트 작성**

Create `lib/wiki/slug.test.mjs`:
```javascript
import { describe, it, expect } from 'vitest';
import { slugify } from './slug.mjs';

describe('slugify', () => {
  it('공백·대소문자 → ASCII kebab', () => {
    expect(slugify('Mixture of Experts')).toBe('mixture-of-experts');
  });
  it('특수문자 런 접고 양끝 트림', () => {
    expect(slugify('  RAG: retrieval!! ')).toBe('rag-retrieval');
  });
  it('비ASCII(한글 only) → 결정적 해시 fallback (ASCII 보장)', () => {
    const s = slugify('전문가 혼합');
    expect(s).toMatch(/^n-[0-9a-f]{6}$/);
    expect(slugify('전문가 혼합')).toBe(s); // 결정적
  });
  it('빈/널 → 빈 문자열', () => {
    expect(slugify('')).toBe('');
    expect(slugify(null)).toBe('');
  });
});
```

- [ ] **Step 2: 실패 확인**

Run: `npx vitest run lib/wiki/slug.test.mjs`
Expected: FAIL — module not found.

- [ ] **Step 3: 구현**

Create `lib/wiki/slug.mjs`:
```javascript
import { createHash } from 'node:crypto';

export function slugify(title) {
  if (title == null || !String(title).trim()) return '';
  const ascii = String(title)
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '') // 라틴 발음기호 제거
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (ascii) return ascii;
  // 비ASCII 제목(예: 한글 only): ASCII 보장을 위해 결정적 해시 suffix
  const h = createHash('sha1').update(String(title)).digest('hex').slice(0, 6);
  return `n-${h}`;
}
```

- [ ] **Step 4: 통과 확인**

Run: `npx vitest run lib/wiki/slug.test.mjs`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/wiki/slug.mjs lib/wiki/slug.test.mjs
git commit -m "feat(wiki): ASCII slug 정규화(+해시 fallback)"
```

---

### Task 3: `lib/wiki/frontmatter.mjs` — 파싱/직렬화/검증(slug ASCII)

**Files:** Create `lib/wiki/frontmatter.mjs`, Test `lib/wiki/frontmatter.test.mjs`

- [ ] **Step 1: 실패 테스트 작성**

Create `lib/wiki/frontmatter.test.mjs`:
```javascript
import { describe, it, expect } from 'vitest';
import { parsePage, serializePage, validateFrontmatter } from './frontmatter.mjs';

const fm = {
  type: 'concept', title: 'Mixture of Experts', slug: 'mixture-of-experts',
  aliases: ['MoE'], sources: ['research/2026-04-27-moe'], related: ['[[transformer]]'],
  confidence: 'high', created: '2026-05-25', updated: '2026-05-26'
};

describe('serialize/parse round-trip', () => {
  it('frontmatter·body 보존', () => {
    const raw = serializePage({ frontmatter: fm, body: '## TL;DR\n본문' });
    const { frontmatter, body } = parsePage(raw);
    expect(frontmatter.slug).toBe('mixture-of-experts');
    expect(frontmatter.sources).toEqual(['research/2026-04-27-moe']);
    expect(body.trim()).toBe('## TL;DR\n본문');
  });
});

describe('validateFrontmatter', () => {
  it('유효 → ok', () => { expect(validateFrontmatter(fm).ok).toBe(true); });
  it('type 오류 → error', () => {
    const r = validateFrontmatter({ ...fm, type: 'note' });
    expect(r.ok).toBe(false); expect(r.errors.join(' ')).toMatch(/type/);
  });
  it('sources 비배열 → error', () => { expect(validateFrontmatter({ ...fm, sources: 'x' }).ok).toBe(false); });
  it('related 누락 → error', () => { const { related, ...rest } = fm; expect(validateFrontmatter(rest).ok).toBe(false); });
  it('confidence 비정상 → error', () => { expect(validateFrontmatter({ ...fm, confidence: 'maybe' }).ok).toBe(false); });
  it('slug에 한글 → error (ASCII만)', () => { expect(validateFrontmatter({ ...fm, slug: '전문가-혼합' }).ok).toBe(false); });
  it('slug 대문자/공백 → error', () => { expect(validateFrontmatter({ ...fm, slug: 'Bad Slug' }).ok).toBe(false); });
});
```

- [ ] **Step 2: 실패 확인**

Run: `npx vitest run lib/wiki/frontmatter.test.mjs`
Expected: FAIL — module not found.

- [ ] **Step 3: 구현**

Create `lib/wiki/frontmatter.mjs`:
```javascript
import YAML from 'yaml';

const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/; // ASCII kebab only

export function parsePage(raw) {
  const text = String(raw ?? '');
  const m = text.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
  if (!m) return { frontmatter: {}, body: text };
  return { frontmatter: YAML.parse(m[1]) ?? {}, body: m[2] ?? '' };
}

export function serializePage({ frontmatter, body }) {
  const yaml = YAML.stringify(frontmatter).trimEnd();
  return `---\n${yaml}\n---\n\n${String(body ?? '').trim()}\n`;
}

export function validateFrontmatter(fm) {
  const errors = [];
  if (fm?.type !== 'concept' && fm?.type !== 'entity') errors.push('type must be concept|entity');
  if (!fm?.title || typeof fm.title !== 'string') errors.push('title required');
  if (!fm?.slug || !SLUG_RE.test(fm.slug)) errors.push('slug must be ASCII kebab-case');
  if (!Array.isArray(fm?.sources)) errors.push('sources must be an array');
  if (!Array.isArray(fm?.related)) errors.push('related must be an array');
  if (fm?.aliases != null && !Array.isArray(fm.aliases)) errors.push('aliases must be an array');
  if (fm?.confidence != null && !['high', 'medium', 'low'].includes(fm.confidence)) errors.push('confidence must be high|medium|low');
  if (!fm?.created) errors.push('created required');
  if (!fm?.updated) errors.push('updated required');
  return { ok: errors.length === 0, errors };
}
```

- [ ] **Step 4: 통과 확인**

Run: `npx vitest run lib/wiki/frontmatter.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/wiki/frontmatter.mjs lib/wiki/frontmatter.test.mjs
git commit -m "feat(wiki): frontmatter 파싱·직렬화·검증(slug ASCII)"
```

---

### Task 4: `lib/wiki/index_log.mjs` — index 재생성 / log / 정확매칭 판정

**Files:** Create `lib/wiki/index_log.mjs`, Test `lib/wiki/index_log.test.mjs`

- [ ] **Step 1: 실패 테스트 작성**

Create `lib/wiki/index_log.test.mjs`:
```javascript
import { describe, it, expect } from 'vitest';
import { rebuildIndex, appendLog, isIngested } from './index_log.mjs';

describe('rebuildIndex', () => {
  it('type별 그룹·slug 정렬 카탈로그', () => {
    const md = rebuildIndex([
      { type: 'concept', slug: 'moe', title: 'MoE' },
      { type: 'entity', slug: 'transformer', title: 'Transformer' },
      { type: 'concept', slug: 'attention', title: 'Attention' },
    ]);
    expect(md).toMatch(/## Concepts/);
    expect(md).toMatch(/## Entities/);
    expect(md.indexOf('attention')).toBeLessThan(md.indexOf('moe'));
    expect(md).toMatch(/\[\[attention\]\]/);
  });
});

describe('appendLog / isIngested (정확 라인매칭)', () => {
  it('append 후 정확 매칭 true', () => {
    const log = appendLog('', { date: '2026-05-25', action: 'ingest', slug: 'research/2026-04-27-moe' });
    expect(isIngested(log, 'research/2026-04-27-moe')).toBe(true);
  });
  it('접두 부분문자열은 false (오탐 방지)', () => {
    const log = '- [2026-05-25] ingest | research/2026-04-27-moe-followup';
    expect(isIngested(log, 'research/2026-04-27-moe')).toBe(false);
  });
  it('없는 소스 false', () => {
    expect(isIngested('- [2026-05-25] ingest | research/a', 'research/b')).toBe(false);
  });
});
```

- [ ] **Step 2: 실패 확인**

Run: `npx vitest run lib/wiki/index_log.test.mjs`
Expected: FAIL — module not found.

- [ ] **Step 3: 구현**

Create `lib/wiki/index_log.mjs`:
```javascript
export function rebuildIndex(pages) {
  const byType = { concept: [], entity: [] };
  for (const p of pages) (byType[p.type] ??= []).push(p);
  const section = (title, list) => {
    if (!list || list.length === 0) return '';
    const lines = [...list].sort((a, b) => a.slug.localeCompare(b.slug))
      .map(p => `- [[${p.slug}]] — ${p.title}`);
    return `## ${title}\n\n${lines.join('\n')}\n`;
  };
  return ['# Wiki Index', '', section('Concepts', byType.concept), section('Entities', byType.entity)]
    .filter(Boolean).join('\n').trimEnd() + '\n';
}

export function appendLog(logText, { date, action, slug }) {
  const line = `- [${date}] ${action} | ${slug}`;
  const base = String(logText ?? '').trimEnd();
  return (base ? base + '\n' : '') + line + '\n';
}

// 정확 라인매칭: "| <slug>" 뒤 토큰이 정확히 일치할 때만 true (접두 부분문자열 오탐 방지)
export function isIngested(logText, sourceSlug) {
  return String(logText ?? '').split('\n').some(line => {
    const idx = line.indexOf('| ');
    return idx >= 0 && line.slice(idx + 2).trim() === sourceSlug;
  });
}
```

- [ ] **Step 4: 통과 확인**

Run: `npx vitest run lib/wiki/index_log.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/wiki/index_log.mjs lib/wiki/index_log.test.mjs
git commit -m "feat(wiki): index 재생성·log·정확매칭 ingest 판정"
```

---

## Phase 2 — ingest (원자·단일 apply + 카탈로그 링크)

### Task 5: `lib/wiki/apply.mjs` — 원자·단일·섹션merge apply

**Files:** Create `lib/wiki/apply.mjs`, Test `lib/wiki/apply.test.mjs`

- [ ] **Step 1: 실패 테스트 작성**

Create `lib/wiki/apply.test.mjs`:
```javascript
import { describe, it, expect, beforeEach } from 'vitest';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { applyIngest } from './apply.mjs';
import { parsePage } from './frontmatter.mjs';

let vault;
beforeEach(async () => { vault = await fs.mkdtemp(path.join(os.tmpdir(), 'wiki-')); });

const plan = {
  source: 'research/2026-04-27-moe',
  pages: [{
    type: 'concept', title: 'Mixture of Experts', slug: 'mixture-of-experts',
    aliases: ['MoE'], sources: ['research/2026-04-27-moe'], confidence: 'high',
    tldr: '라우터가 토큰을 일부 전문가에게만 보낸다.',
    perspective: '- top-k 전문가 선택 [1].', links: ['attention-mechanism'],
  }],
};
const read = (p) => fs.readFile(path.join(vault, p), 'utf8');

describe('applyIngest', () => {
  it('새 페이지: 섹션 본문·related·index·log 1줄', async () => {
    const r = await applyIngest({ vaultDir: vault, pagePlan: plan, date: '2026-05-25' });
    expect(r.created).toContain('concepts/mixture-of-experts.md');
    const { frontmatter, body } = parsePage(await read('concepts/mixture-of-experts.md'));
    expect(frontmatter.related).toEqual(['[[attention-mechanism]]']);
    expect(body).toMatch(/## TL;DR/);
    expect(body).toMatch(/### research\/2026-04-27-moe/);
    expect(body).toMatch(/## 관련 개념/);
    expect(body).toMatch(/\[\[attention-mechanism\]\]/);
    expect(await read('index.md')).toMatch(/\[\[mixture-of-experts\]\]/);
    expect((await read('log.md')).match(/ingest \| research\/2026-04-27-moe/g)).toHaveLength(1);
  });

  it('같은 소스 두 번: 멱등(중복 섹션·중복 log 없음)', async () => {
    await applyIngest({ vaultDir: vault, pagePlan: plan, date: '2026-05-25' });
    await applyIngest({ vaultDir: vault, pagePlan: plan, date: '2026-05-26' });
    const body = (await read('concepts/mixture-of-experts.md'));
    expect(body.match(/### research\/2026-04-27-moe/g)).toHaveLength(1);
    expect(body.match(/## 관련 개념/g)).toHaveLength(1);
    expect((await read('log.md')).match(/ingest \|/g)).toHaveLength(1);
  });

  it('다른 소스 merge: sources 합집합 + 섹션 2개 + updated 갱신', async () => {
    await applyIngest({ vaultDir: vault, pagePlan: plan, date: '2026-05-25' });
    const p2 = structuredClone(plan);
    p2.source = 'research/2026-05-01-moe-followup';
    p2.pages[0].sources = ['research/2026-05-01-moe-followup'];
    p2.pages[0].perspective = '- 로드밸런싱 개선 [1].';
    p2.pages[0].links = ['transformer'];
    const r = await applyIngest({ vaultDir: vault, pagePlan: p2, date: '2026-05-26' });
    expect(r.merged).toContain('concepts/mixture-of-experts.md');
    const { frontmatter, body } = parsePage(await read('concepts/mixture-of-experts.md'));
    expect(frontmatter.sources).toEqual(['research/2026-04-27-moe', 'research/2026-05-01-moe-followup']);
    expect(frontmatter.related.sort()).toEqual(['[[attention-mechanism]]', '[[transformer]]']);
    expect(frontmatter.updated).toBe('2026-05-26');
    expect(body.match(/### research\//g)).toHaveLength(2);
  });

  it('누적 sources merge: 섹션 키는 pagePlan.source (sources[0] 아님)', async () => {
    await applyIngest({ vaultDir: vault, pagePlan: plan, date: '2026-05-25' });
    const p2 = structuredClone(plan);
    p2.source = 'research/2026-05-01-moe-followup';
    // LLM이 누적 sources를 원본 먼저 순서로 내보낸 경우(sources[0] = 이전 세션)
    p2.pages[0].sources = ['research/2026-04-27-moe', 'research/2026-05-01-moe-followup'];
    p2.pages[0].perspective = '- 후속 관점 [1].';
    await applyIngest({ vaultDir: vault, pagePlan: p2, date: '2026-05-26' });
    const { body } = parsePage(await read('concepts/mixture-of-experts.md'));
    expect(body).toMatch(/### research\/2026-04-27-moe\n/);        // 원본 섹션 보존(덮어쓰기 아님)
    expect(body).toMatch(/### research\/2026-05-01-moe-followup/); // 새 세션 섹션은 pagePlan.source 키로
    expect(body).toMatch(/후속 관점/);
  });

  it('다중 줄 perspective 라운드트립: 모든 줄 보존 (앵커 lookahead 회귀 방지)', async () => {
    const ml = structuredClone(plan);
    ml.pages[0].perspective = '- 첫째 줄 [1].\n- 둘째 줄 [2].\n- 셋째 줄 [3].';
    await applyIngest({ vaultDir: vault, pagePlan: ml, date: '2026-05-25' });
    // 다른 세션으로 merge → 기존 3줄 섹션을 parseBody로 재파싱해야 함(절단되면 손실)
    const p2 = structuredClone(plan);
    p2.source = 'research/2026-05-02-x';
    p2.pages[0].sources = ['research/2026-05-02-x'];
    p2.pages[0].perspective = '- 새 줄 [1].';
    await applyIngest({ vaultDir: vault, pagePlan: p2, date: '2026-05-26' });
    const { body } = parsePage(await read('concepts/mixture-of-experts.md'));
    expect(body).toMatch(/첫째 줄/);
    expect(body).toMatch(/둘째 줄/);
    expect(body).toMatch(/셋째 줄/); // 회귀(줄끝 $ 절단) 시 사라짐
  });

  it('원자성: 멀티페이지 중 하나라도 invalid면 아무것도 안 쓴다', async () => {
    const bad = structuredClone(plan);
    // sources 는 불변식(pagePlan.source 포함)을 만족시키되 type 만 위반 → 검증 단계서 throw
    bad.pages.push({ type: 'note', title: 'X', slug: 'x', sources: ['research/2026-04-27-moe'], tldr: '', perspective: '', links: [] });
    await expect(applyIngest({ vaultDir: vault, pagePlan: bad, date: '2026-05-25' })).rejects.toThrow(/type/);
    await expect(read('concepts/mixture-of-experts.md')).rejects.toThrow(); // 첫 페이지도 안 쓰임
    await expect(read('log.md')).rejects.toThrow();
  });
});
```

- [ ] **Step 2: 실패 확인**

Run: `npx vitest run lib/wiki/apply.test.mjs`
Expected: FAIL — module not found.

- [ ] **Step 3: 구현**

Create `lib/wiki/apply.mjs`:
```javascript
import fs from 'node:fs/promises';
import path from 'node:path';
import { parsePage, serializePage, validateFrontmatter } from './frontmatter.mjs';
import { rebuildIndex, appendLog, isIngested } from './index_log.mjs';

const DIR = { concept: 'concepts', entity: 'entities' };
const uniq = (a) => [...new Set(a)];
const relSlugs = (related) => (related ?? []).map(s => String(s).replace(/^\[\[|\]\]$/g, ''));

function parseBody(body) {
  const text = String(body ?? '');
  const tldrM = text.match(/## TL;DR\s*\n([\s\S]*?)(?:\n## |$)/);
  const tldr = tldrM ? tldrM[1].trim() : '';
  const perspectives = {};
  const persBlock = text.match(/## 출처별 관점\s*\n([\s\S]*?)(?:\n## 관련 개념|$)/);
  if (persBlock) {
    // source heading(^### research/...)만 매칭 — perspective 내부 하위 heading 오염 방지.
    // 종료 lookahead는 (?![\s\S])(=문자열 끝)을 쓴다. m 플래그의 $ 는 줄끝마다 매칭돼
    // lazy 본문을 첫 줄에서 절단하는 회귀가 있으므로 $ 를 쓰지 않는다.
    const re = /^### (research\/\S+)[ \t]*\n([\s\S]*?)(?=\n### research\/|(?![\s\S]))/gm;
    let m;
    while ((m = re.exec(persBlock[1])) !== null) perspectives[m[1].trim()] = m[2].trim();
  }
  return { tldr, perspectives };
}

function renderBody({ tldr, perspectives, relatedSlugs }) {
  const pers = Object.entries(perspectives)
    .map(([src, txt]) => `### ${src}\n${txt.trim()}`).join('\n\n');
  let out = `## TL;DR\n${(tldr ?? '').trim()}\n\n## 출처별 관점\n\n${pers}\n`;
  if (relatedSlugs.length) out += `\n## 관련 개념\n\n${relatedSlugs.map(s => `- [[${s}]]`).join('\n')}\n`;
  return out;
}

async function listPages(vaultDir) {
  const out = [];
  for (const [type, dir] of Object.entries(DIR)) {
    let files = [];
    try { files = await fs.readdir(path.join(vaultDir, dir)); } catch { continue; }
    for (const f of files.filter(f => f.endsWith('.md'))) {
      const { frontmatter } = parsePage(await fs.readFile(path.join(vaultDir, dir, f), 'utf8'));
      out.push({ type, slug: frontmatter.slug ?? f.replace(/\.md$/, ''), title: frontmatter.title ?? '' });
    }
  }
  return out;
}

async function writeAtomic(abs, content) {
  const tmp = `${abs}.tmp-${process.pid}`;
  await fs.writeFile(tmp, content);
  await fs.rename(tmp, abs); // rename = 원자적 교체 (부분쓰기 방지)
}

export async function applyIngest({ vaultDir, pagePlan, date }) {
  // 1) 검증·준비 전체 (디스크 쓰기 전)
  const prepared = [];
  for (const p of pagePlan.pages) {
    // 불변식: 이번 세션(pagePlan.source)은 반드시 page.sources 에 포함
    if (!(p.sources ?? []).includes(pagePlan.source))
      throw new Error(`page ${p.slug}: sources must include pagePlan.source (${pagePlan.source})`);
    const rel = `${DIR[p.type] ?? 'concepts'}/${p.slug}.md`;
    const abs = path.join(vaultDir, rel);
    let existing = null;
    try { existing = parsePage(await fs.readFile(abs, 'utf8')); } catch {}

    // links 는 soft-link 허용(미존재 페이지 = 향후 생성 대상; lint 가 broken-link 로 표시)
    const relatedSlugs = uniq([
      ...(existing ? relSlugs(existing.frontmatter.related) : []),
      ...(p.links ?? []),
    ]);
    const fm = existing
      ? { ...existing.frontmatter,
          sources: uniq([...(existing.frontmatter.sources ?? []), ...(p.sources ?? [])]),
          aliases: uniq([...(existing.frontmatter.aliases ?? []), ...(p.aliases ?? [])]),
          related: relatedSlugs.map(s => `[[${s}]]`),
          confidence: p.confidence ?? existing.frontmatter.confidence ?? 'medium',
          updated: date }
      : { type: p.type, title: p.title, slug: p.slug,
          aliases: uniq(p.aliases ?? []), sources: uniq(p.sources ?? []),
          related: relatedSlugs.map(s => `[[${s}]]`),
          confidence: p.confidence ?? 'medium', created: date, updated: date };

    const v = validateFrontmatter(fm);
    if (!v.ok) throw new Error(`invalid frontmatter for ${p.slug}: ${v.errors.join('; ')}`);

    const prev = existing ? parseBody(existing.body) : { tldr: '', perspectives: {} };
    const tldr = prev.tldr || p.tldr || '';
    const perspectives = { ...prev.perspectives };
    // 섹션 키 = 지금 ingest 중인 세션(pagePlan.source). 누적 sources[0] 오기록 방지(claude#1).
    if (p.perspective) perspectives[pagePlan.source] = p.perspective;
    const body = renderBody({ tldr, perspectives, relatedSlugs });
    prepared.push({ abs, rel, fm, body, isNew: !existing });
  }

  // 2) 전부 검증 통과 후에만 쓰기 (tmp+rename 원자 교체)
  const created = [], merged = [];
  for (const pr of prepared) {
    await fs.mkdir(path.dirname(pr.abs), { recursive: true });
    await writeAtomic(pr.abs, serializePage({ frontmatter: pr.fm, body: pr.body }));
    (pr.isNew ? created : merged).push(pr.rel);
  }

  // 3) index 재생성 (tmp+rename)
  await writeAtomic(path.join(vaultDir, 'index.md'), rebuildIndex(await listPages(vaultDir)));

  // 4) log 1회 (정확매칭 dedupe, tmp+rename)
  const logPath = path.join(vaultDir, 'log.md');
  let log = ''; try { log = await fs.readFile(logPath, 'utf8'); } catch {}
  if (!isIngested(log, pagePlan.source))
    await writeAtomic(logPath, appendLog(log, { date, action: 'ingest', slug: pagePlan.source }));

  return { source: pagePlan.source, created, merged };
}
```

- [ ] **Step 4: 통과 확인**

Run: `npx vitest run lib/wiki/apply.test.mjs`
Expected: PASS (6 tests).

- [ ] **Step 5: CLI 래퍼 추가**

Append to `lib/wiki/apply.mjs`:
```javascript
// CLI: node lib/wiki/apply.mjs --vault <dir> --plan <plan.json> --date <YYYY-MM-DD>
if (import.meta.url === `file://${process.argv[1]}`) {
  const get = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
  const pagePlan = JSON.parse(await fs.readFile(get('--plan'), 'utf8'));
  const r = await applyIngest({ vaultDir: get('--vault'), pagePlan, date: get('--date') ?? new Date().toISOString().slice(0, 10) });
  process.stdout.write(JSON.stringify(r) + '\n');
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/wiki/apply.mjs lib/wiki/apply.test.mjs
git commit -m "feat(wiki): 원자·단일·섹션merge apply + CLI"
```

---

### Task 6: `commands/wiki.md` — `/wiki ingest`(카탈로그 링크, 단일 apply)

**Files:** Create `commands/wiki.md`

- [ ] **Step 1: 명령 파일 작성**

Create `commands/wiki.md`:
```markdown
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
```

- [ ] **Step 2: 수동 점검**

Run: `grep -nE "정확매칭|index.md|apply.mjs|단일 apply" commands/wiki.md`
Expected: 네 참조 존재.

- [ ] **Step 3: Commit**

```bash
git add commands/wiki.md
git commit -m "feat(wiki): /wiki 명령 + ingest(카탈로그 링크, 단일 apply)"
```

---

### Task 7: bats 계약 — apply CLI(생성·멱등 merge·log 1줄)

**Files:** Create `tests/research-engine/fixtures/wiki/plan-moe.json`, `tests/research-engine/wiki.test.sh`

- [ ] **Step 1: 픽스처**

Create `tests/research-engine/fixtures/wiki/plan-moe.json`:
```json
{
  "source": "research/2026-04-27-moe",
  "pages": [
    { "type": "concept", "title": "Mixture of Experts", "slug": "mixture-of-experts",
      "aliases": ["MoE"], "sources": ["research/2026-04-27-moe"], "confidence": "high",
      "tldr": "라우터가 토큰을 일부 전문가에게만 보낸다.",
      "perspective": "- top-k 전문가 선택 [1].", "links": ["transformer"] },
    { "type": "entity", "title": "Transformer", "slug": "transformer",
      "sources": ["research/2026-04-27-moe"], "confidence": "high",
      "tldr": "attention 기반 시퀀스 아키텍처.",
      "perspective": "- self-attention 으로 토큰 상호작용 [1].", "links": [] }
  ]
}
```

- [ ] **Step 2: bats 테스트**

Create `tests/research-engine/wiki.test.sh`:
```bash
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
```

- [ ] **Step 3: 실행 확인**

Run: `bats tests/research-engine/wiki.test.sh`
Expected: PASS (2 tests).

- [ ] **Step 4: Commit**

```bash
git add tests/research-engine/fixtures/wiki/ tests/research-engine/wiki.test.sh
git commit -m "test(wiki): apply CLI bats(생성·멱등)"
```

---

## Phase 3 — lint

### Task 8: `lib/wiki/lint.mjs` + `/wiki lint`

**Files:** Create `lib/wiki/lint.mjs`, Test `lib/wiki/lint.test.mjs`; Modify `commands/wiki.md`, `tests/research-engine/wiki.test.sh`

- [ ] **Step 1: 실패 테스트 작성**

Create `lib/wiki/lint.test.mjs`:
```javascript
import { describe, it, expect } from 'vitest';
import { lintVault } from './lint.mjs';

const pages = [
  { slug: 'a', type: 'concept', frontmatter: { title: 'A', sources: ['research/x'], related: ['[[b]]'] }, body: '## 출처별 관점\n### research/x\n- 주장 [1]' },
  { slug: 'b', type: 'concept', frontmatter: { title: 'B', sources: [], related: [] }, body: '## 출처별 관점\n무출처 주장' },                 // unsourced
  { slug: 'c', type: 'concept', frontmatter: { title: 'C', sources: ['research/y'], related: ['[[ghost]]'] }, body: '본문' },               // broken-link
  { slug: 'd', type: 'entity', frontmatter: { title: 'D', sources: ['research/z'], related: [] }, body: '링크 없음' },                      // orphan
  { slug: 'e', type: 'concept', frontmatter: { title: 'A', sources: ['research/w'], related: ['[[a]]'] }, body: '## 출처별 관점\n### research/w\n- 주장 [1]' }, // duplicate-title
];

describe('lintVault', () => {
  const { findings } = lintVault({ pages });
  const has = (rule, slug) => findings.some(f => f.rule === rule && f.slug === slug);
  it('무출처', () => expect(has('unsourced', 'b')).toBe(true));
  it('끊긴 링크(related)', () => expect(has('broken-link', 'c')).toBe(true));
  it('고아(인바운드·아웃바운드 없음)', () => expect(has('orphan', 'd')).toBe(true));
  it('b는 a가 링크 → orphan 아님', () => expect(has('orphan', 'b')).toBe(false));
  it('중복 이름 (a, e — title 정규화 후 동일)', () => { expect(has('duplicate-name', 'a')).toBe(true); expect(has('duplicate-name', 'e')).toBe(true); });
  it('정상 a는 무출처/고아 아님', () => { expect(has('unsourced', 'a')).toBe(false); expect(has('orphan', 'a')).toBe(false); });
});
```

- [ ] **Step 2: 실패 확인**

Run: `npx vitest run lib/wiki/lint.test.mjs`
Expected: FAIL — module not found.

- [ ] **Step 3: 구현**

Create `lib/wiki/lint.mjs`:
```javascript
const relSlugs = (related) => (related ?? []).map(s => String(s).replace(/^\[\[|\]\]$/g, ''));

export function lintVault({ pages }) {
  const findings = [];
  const slugSet = new Set(pages.map(p => p.slug));
  const inbound = new Set();
  for (const p of pages) for (const t of relSlugs(p.frontmatter?.related)) if (slugSet.has(t)) inbound.add(t);

  // title + aliases 를 한 namespace 로 정규화(NFKC+trim+lower) → 교차·대소문자 중복까지 탐지
  const norm = (s) => String(s).normalize('NFKC').trim().toLowerCase();
  const nameToSlugs = {};
  for (const p of pages) {
    const names = [p.frontmatter?.title, ...(p.frontmatter?.aliases ?? [])].filter(Boolean);
    for (const n of new Set(names.map(norm))) (nameToSlugs[n] ??= new Set()).add(p.slug);
  }

  for (const p of pages) {
    const outs = relSlugs(p.frontmatter?.related);
    const sources = p.frontmatter?.sources ?? [];
    const body = String(p.body ?? '');
    const hasClaims = /\S/.test(body.replace(/^#.*$/gm, '').trim());

    if ((!Array.isArray(sources) || sources.length === 0) && hasClaims)
      findings.push({ rule: 'unsourced', slug: p.slug, message: 'sources 비어있음' });

    // citation: 본문 ### research/<slug> 섹션이 모두 frontmatter.sources 안에 있어야 함
    const sectionSrcs = [...body.matchAll(/^### (research\/\S+)/gm)].map(m => m[1]);
    if (/\[\d+\]/.test(body) && (sectionSrcs.length === 0 || sources.length === 0))
      findings.push({ rule: 'citation-unresolved', slug: p.slug, message: '[n] 인용에 대응 섹션/출처 없음' });
    for (const s of sectionSrcs) if (!sources.includes(s))
      findings.push({ rule: 'citation-unresolved', slug: p.slug, message: `섹션 ${s} 가 sources에 없음` });

    for (const t of outs) if (!slugSet.has(t))
      findings.push({ rule: 'broken-link', slug: p.slug, message: `끊긴 링크: [[${t}]]` });

    if (!outs.some(t => slugSet.has(t)) && !inbound.has(p.slug))
      findings.push({ rule: 'orphan', slug: p.slug, message: '인바운드·아웃바운드 링크 없음' });

    const names = [p.frontmatter?.title, ...(p.frontmatter?.aliases ?? [])].filter(Boolean);
    for (const n of new Set(names.map(norm)))
      if (nameToSlugs[n] && nameToSlugs[n].size > 1)
        findings.push({ rule: 'duplicate-name', slug: p.slug, message: `중복 이름(title/alias): ${n}` });
  }
  return { findings };
}

// CLI: node lib/wiki/lint.mjs --vault <dir>
if (import.meta.url === `file://${process.argv[1]}`) {
  const fs = await import('node:fs/promises');
  const path = await import('node:path');
  const { parsePage } = await import('./frontmatter.mjs');
  const get = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
  const vaultDir = get('--vault') ?? path.join(process.cwd(), 'wiki');
  const pages = [];
  for (const [type, dir] of Object.entries({ concept: 'concepts', entity: 'entities' })) {
    let files = [];
    try { files = await fs.readdir(path.join(vaultDir, dir)); } catch { continue; }
    for (const f of files.filter(f => f.endsWith('.md'))) {
      const { frontmatter, body } = parsePage(await fs.readFile(path.join(vaultDir, dir, f), 'utf8'));
      pages.push({ slug: frontmatter.slug ?? f.replace(/\.md$/, ''), type, frontmatter, body });
    }
  }
  process.stdout.write(JSON.stringify(lintVault({ pages }), null, 2) + '\n');
}
```

- [ ] **Step 4: 통과 확인**

Run: `npx vitest run lib/wiki/lint.test.mjs`
Expected: PASS.

- [ ] **Step 5: `commands/wiki.md`의 `## Action: lint` 채우기**

```markdown
## Action: lint
1. `node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/lint.mjs" --vault "${VAULT}"` → findings JSON.
2. rule별로 묶어 한글 표로 보고(unsourced/citation-unresolved/broken-link/orphan/duplicate-name).
3. (MVP) `--fix`는 **보고 + 수정 안내**만(결정적 자동수정은 후속 spec). 예: broken-link는 어느 page의 `related`에서 어떤 `[[slug]]`를 지울지 안내.
```

- [ ] **Step 6: bats 추가** (`tests/research-engine/wiki.test.sh`)

```bash
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
```

- [ ] **Step 7: 실행 확인**

Run: `bats tests/research-engine/wiki.test.sh`
Expected: PASS (3 tests).

- [ ] **Step 8: Commit**

```bash
git add lib/wiki/lint.mjs lib/wiki/lint.test.mjs commands/wiki.md tests/research-engine/wiki.test.sh
git commit -m "feat(wiki): lint(무출처·미해결인용·끊긴링크·고아·중복) + /wiki lint"
```

---

## Phase 4 — query

### Task 9: `/wiki query` (인용 합성 + 환류 가드레일)

**Files:** Modify `commands/wiki.md`

- [ ] **Step 1: `## Action: query` 채우기**

```markdown
## Action: query
인자: `"<질문>"` [`--file`]
1. 후보 페이지 찾기 (임베딩 없음): `grep -ril "<핵심어>" "${VAULT}/concepts" "${VAULT}/entities"` + `wiki/index.md` 카탈로그를 훑어 관련 slug 선정.
2. 후보 페이지를 읽어 **인용과 함께** 한글로 합성 답변. 각 사실에 출처 페이지 slug + 그 페이지의 `### research/<slug>` 인용을 명시. raw `research/`는 재독 금지(위키가 source-of-truth).
3. **(MVP) `--file` 환류는 out-of-scope** — query 답변은 여러 위키 페이지·여러 research 세션을 합성하므로 단일 `### research/<slug>` 섹션 계약(pagePlan)에 안전히 매핑되지 않고 환각 전파 위험이 가장 크다. 다중-source pagePlan(`perspectives: [{source, body}]`) 도입을 후속 spec으로 미룬다. MVP는 **읽기 전용 답변**만.
4. 답변을 인용 페이지 slug와 함께 보고.
```

- [ ] **Step 2: 수동 점검**

Run: `grep -nE "Action: query|out-of-scope|읽기 전용" commands/wiki.md`
Expected: 세 참조 존재.

- [ ] **Step 3: Commit**

```bash
git add commands/wiki.md
git commit -m "feat(wiki): /wiki query(인용 합성 + 환류 가드레일)"
```

---

## Phase 5 — 발행 + Codex 패리티

### Task 10: `scripts/wiki_publish.sh` + `/wiki publish`

**Files:** Create `scripts/wiki_publish.sh`; Modify `commands/wiki.md`, `tests/research-engine/wiki.test.sh`

- [ ] **Step 1: 발행 스크립트 (QUARTZ_DIR = vault 밖, build smoke, rsync 배포)**

Create `scripts/wiki_publish.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
# wiki/ 콘텐츠를 Quartz 정적 사이트로 빌드(+smoke). --deploy면 rsync 배포.
VAULT="${VAULT:-$(pwd)/wiki}"
QUARTZ_DIR="${QUARTZ_DIR:-$(pwd)/wiki-site}"   # vault 밖 (nested git/ignore 충돌 방지)
DEPLOY="${1:-}"

if [ ! -d "${QUARTZ_DIR}" ]; then
  echo "Quartz 미설치. 1회 설치:" >&2
  echo "  git clone https://github.com/jackyzha0/quartz \"${QUARTZ_DIR}\" && (cd \"${QUARTZ_DIR}\" && npm i)" >&2
  exit 1
fi

CONTENT="${QUARTZ_DIR}/content"
rm -rf "${CONTENT}"; mkdir -p "${CONTENT}"
cp -r "${VAULT}/concepts" "${VAULT}/entities" "${CONTENT}/" 2>/dev/null || true
cp "${VAULT}/index.md" "${CONTENT}/index.md" 2>/dev/null || true

( cd "${QUARTZ_DIR}" && npx quartz build )
# smoke: index.html 생성 확인
test -f "${QUARTZ_DIR}/public/index.html" || { echo "publish smoke 실패: public/index.html 없음" >&2; exit 1; }
echo "built+smoke ok: ${QUARTZ_DIR}/public"

if [ "${DEPLOY}" = "--deploy" ]; then
  # 배포는 명시적 rsync 만 (임의 명령 eval 금지 — 셸 인젝션 회피)
  : "${WIKI_DEPLOY_TARGET:?WIKI_DEPLOY_TARGET 미설정 — 예: user@host:/var/www/wiki}"
  rsync -a --delete "${QUARTZ_DIR}/public/" "${WIKI_DEPLOY_TARGET}/"
  echo "deployed → ${WIKI_DEPLOY_TARGET}"
fi
```

- [ ] **Step 2: `## Action: publish` 채우기**

```markdown
## Action: publish
인자: `[--deploy]`
1. `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki_publish.sh" <--deploy?>` (QUARTZ_DIR는 vault 밖, build+index smoke 포함).
2. 산출물(`wiki-site/public`) 경로 보고. `--deploy`면 `WIKI_DEPLOY_TARGET`(예: `user@host:/var/www/wiki`)로 rsync 배포(hetzner LXC 또는 정적 호스트).
```

- [ ] **Step 3: bats smoke (Quartz 없으면 안내 후 비정상 종료)** (`tests/research-engine/wiki.test.sh`)

```bash
@test "publish: Quartz 미설치면 설치 안내 후 비정상 종료" {
  QUARTZ_DIR="${TMP}/no-quartz" VAULT="${VAULT}" run bash "${REPO_ROOT}/scripts/wiki_publish.sh"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Quartz 미설치"
}
```

- [ ] **Step 4: 문법 + 실행 확인**

Run: `bash -n scripts/wiki_publish.sh && bats tests/research-engine/wiki.test.sh`
Expected: 문법 0, bats PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/wiki_publish.sh commands/wiki.md tests/research-engine/wiki.test.sh
git commit -m "feat(wiki): /wiki publish(Quartz vault 밖, build smoke, rsync 배포)"
```

---

### Task 11: package.json 테스트 타깃 · Codex SKILL 패리티 · 버전 bump

**Files:** Modify `package.json`, `skills/research-engine/SKILL.md`, `.claude-plugin/plugin.json`

- [ ] **Step 1: package.json test:bats에 wiki 추가**

`test:bats` 스크립트 끝에 ` tests/research-engine/wiki.test.sh` 추가. (`test:unit`은 `lib` 전체 → `lib/wiki/*.test.mjs` 자동 포함.)

- [ ] **Step 2: SKILL.md에 위키 워크플로 추가**

`skills/research-engine/SKILL.md` 끝에:
```markdown
## Wiki Workflow (Codex 패리티)
`commands/wiki.md`가 정본. Codex에서 동일 계약으로:
1. `wiki/` 없으면 생성 + `lib/wiki/AGENTS.template.md` → `wiki/AGENTS.md` 복사 + 빈 `index.md`.
2. ingest: `research/<slug>`(raw 불변) + `wiki/index.md` 카탈로그 읽기 → 헌법대로 pagePlan JSON(tldr/perspective/links, links는 카탈로그 실재 slug만) 생성 → `node lib/wiki/apply.mjs --vault wiki --plan <tmp> --date <today>` **1회**.
3. lint: `node lib/wiki/lint.mjs --vault wiki`.
4. query: grep/카탈로그 후보 → 위키 페이지에서 인용 합성(읽기 전용). `--file` 환류·`lint --fix` 자동수정은 MVP out-of-scope(후속).
5. publish: `scripts/wiki_publish.sh`.
한글 합성, raw 절대 수정 금지, 무출처 주장 금지, slug ASCII.
```

- [ ] **Step 3: 버전 bump**

Run:
```bash
cd /home/taejin/projects/research-engine
node -e "const f='.claude-plugin/plugin.json';const j=require('./'+f);const [a,b]=j.version.split('.');j.version=`${a}.${+b+1}.0`;require('fs').writeFileSync(f,JSON.stringify(j,null,2)+'\n')"
```

- [ ] **Step 4: 전체 테스트**

Run: `npm run test:unit && npm run test:bats`
Expected: 기존 + wiki 전부 PASS.

- [ ] **Step 5: Commit**

```bash
git add package.json skills/research-engine/SKILL.md .claude-plugin/plugin.json
git commit -m "feat(wiki): 테스트 타깃·Codex SKILL 패리티·버전 bump"
```

---

## 첫 실사용 (구현 후 수동 검증)
1. `/wiki ingest 2026-04-27-moe-llm-routing-improvements-2025` — 단일 세션, `wiki/concepts/` 페이지·`index.md`·`log.md` 확인.
2. `/wiki ingest --all` — 92세션 일괄(정확매칭 skip 재개) → 종료 후 `/wiki lint` 자동 요약.
3. Obsidian으로 `wiki/` 열어 graph·backlink 시각 확인 (CLAUDE.md "반드시 눈으로 검증").
4. `/wiki query "MoE 라우팅 개선 핵심은?"` — 인용 합성.
5. `/wiki publish` — Quartz 빌드+smoke 후 사이트 확인.

---

## Self-Review (작성 후 점검)
- **Spec 커버리지**: §6 스키마→Task3, §7 4액션→Task6/8/9/10, §8 카탈로그 링크→Task6(ingest 4번 links), §9 라이트 가드레일(sources/인용/lint)→Task8, §10 시드/연동→Task6(--all/--new), §11 발행(vault밖+smoke)→Task10, §12 테스트→전 Task, §5 gitignore→Task1, Codex 패리티→Task11. 갭 없음.
- **1차 리뷰 반영**: 더블apply 제거(링크 apply 전 확정, 단일 apply: Task5/6) / isIngested 정확매칭(Task4) / apply 원자성 validate-all→write-all→log-once(Task5) / 섹션 merge·related 단일신뢰원·관련개념 렌더링(Task5) / 임베딩 제거→카탈로그 링크(Task1 deps, Task6) / slug ASCII(Task2,3) / citation+중복 lint(Task8) / Quartz vault밖+smoke+rsync(Task10) / --all vs --new 의미 명확화(Task6).
- **2차 리뷰 반영**: perspective 섹션 키 = `pagePlan.source`(누적 sources 오기록 방지) + 불변식 검증 + 누적-sources 테스트(Task5) / parseBody `^### research/...` 앵커링(하위 heading 오염 방지, Task5) / tmp+rename 진짜 원자 쓰기(Task5) / citation `### research/<slug>` ⊆ sources 검사(Task8) / duplicate-name 정규화(NFKC+trim+lower, title·alias 통합 namespace, Task8) / soft-link 의도 명시(미존재=향후 생성, lint가 표시: Task5/6) / `--rebuild` dedupe 우회 명시(Task6) / `query --file`·`lint --fix`는 MVP out-of-scope 강등(Task8/9).
- **Placeholder**: "(Task N)"은 Task6 명령 골격의 자리표시 → Task8/9/10에서 완전한 내용으로 교체(각 Task에 교체 텍스트 포함). 코드 스텝엔 placeholder 없음.
- **Type 일관성**: pagePlan(tldr/perspective/links) ↔ apply.mjs parseBody/renderBody, `applyIngest({vaultDir,pagePlan,date})`, `isIngested(log,slug)`(정확매칭), `lintVault({pages})`(frontmatter.related 기반), `relSlugs` 헬퍼가 apply·lint에서 동일 정의. frontmatter related = 링크 단일 신뢰원으로 apply/lint/index 일관.
