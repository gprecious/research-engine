# LLM Wiki → Obsidian + Librarian Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** research-engine `/wiki` 를 harry Obsidian vault 의 단일 글로벌 위키로 타게팅(이름 기반)·`#ai-generated` 태깅하고, 월간 librarian(7-stage 티어드 health-check) + dream/evolve 위키 적용 + promotion gate 를 추가한다.

**Architecture:** 기존 `lib/wiki/*.mjs`(apply/lint/frontmatter/index_log/slug) + `commands/wiki.md` 를 확장. 결정적 로직은 `.mjs`(vitest), 판단 로직은 `commands/*.md`(에이전트). 위험 산출은 `_drafts/` 격리 후 `promote` 로 승격.

**Tech Stack:** Node ESM(`.mjs`), `yaml`, vitest(`*.test.mjs`), bats(통합), Claude Code 명령(`commands/*.md`), Agent tool.

**Spec:** `docs/superpowers/specs/2026-06-09-llm-wiki-librarian-design.md`

**Decomposition (각 Phase = 독립 동작 SW, 순차 의존):**
- **P1 — Foundation**: vault 이름 해석 + 태깅 → `/wiki ingest` 가 harry vault 에 태깅된 페이지 누적. (이 plan 에 full bite-sized)
- **P2 — Librarian**: lint 확장 + 티어드 자동/draft apply.
- **P3 — Promote**: `_drafts/` → live 승격(+critic).
- **P4 — dream/evolve(wiki)**: synthesis/gap + 스키마 진화.
- **P5 — Publish/Trigger/Release**: 발행 제외 + 월간 cron + 버전.

> P2~P5 는 P1 산출에 의존하므로 각 Phase 진입 시 동일 TDD 패턴(실패테스트→최소구현→통과→commit)으로 전개한다. 본 문서는 P1 을 bite-sized 로, P2~P5 를 파일/인터페이스/테스트/수용기준 단위로 정의한다(cmux+codex 워커 단위와 일치).

**테스트 명령:** mjs → `npx vitest run lib/wiki/<file>.test.mjs` · 통합 → `bats tests/research-engine/wiki.test.sh`

---

## Phase 0: 작업 준비

- [ ] **Step 1: 브랜치 생성**

```bash
cd /Users/taejin/Documents/dev/research-engine
git checkout main && git pull --ff-only
git checkout -b feat/wiki-obsidian-librarian
```

- [ ] **Step 2: 테스트 러너 동작 확인 (기존 통과 baseline)**

Run: `npx vitest run lib/wiki/ && echo BASELINE_OK`
Expected: 기존 frontmatter/slug/index_log/lint/apply 테스트 PASS, `BASELINE_OK`.

---

## Phase 1 — Foundation: vault 이름 해석 + 태깅

### Task 1.1: `vault_resolve.mjs` — 이름 기반 vault 해석

**Files:**
- Create: `lib/wiki/vault_resolve.mjs`
- Test: `lib/wiki/vault_resolve.test.mjs`

- [ ] **Step 1: 실패 테스트 작성**

```js
// lib/wiki/vault_resolve.test.mjs
import { describe, it, expect } from 'vitest';
import { resolveVault } from './vault_resolve.mjs';

// configReader: (paths[]) => { vaults: { id: {path, open, ts} } } | null
const cfg = () => ({ vaults: {
  a: { path: '/Users/x/Documents/obsidian/harry', open: true,  ts: 200 },
  b: { path: '/icloud/harry',                      open: false, ts: 100 },
  c: { path: '/Users/x/other',                     open: true,  ts: 300 },
}});

describe('resolveVault precedence', () => {
  it('1) WIKI_VAULT 절대경로가 최우선', () => {
    const r = resolveVault({ env: { WIKI_VAULT: '/abs/wiki', LLM_OBSIDIAN_VAULT_NAME: 'harry' }, cwd: '/proj', readConfig: cfg });
    expect(r.dir).toBe('/abs/wiki'); expect(r.mode).toBe('explicit');
  });
  it('2) 이름 → obsidian.json 해석 + 하위폴더, open/ts 우선', () => {
    const r = resolveVault({ env: { LLM_OBSIDIAN_VAULT_NAME: 'harry', LLM_WIKI_SUBDIR: 'LLM-Wiki' }, cwd: '/proj', readConfig: cfg });
    expect(r.dir).toBe('/Users/x/Documents/obsidian/harry/LLM-Wiki'); expect(r.mode).toBe('name');
  });
  it('2b) SUBDIR 기본값 LLM-Wiki', () => {
    const r = resolveVault({ env: { LLM_OBSIDIAN_VAULT_NAME: 'harry' }, cwd: '/proj', readConfig: cfg });
    expect(r.dir).toBe('/Users/x/Documents/obsidian/harry/LLM-Wiki');
  });
  it('3) env 없음 → <cwd>/wiki 폴백', () => {
    const r = resolveVault({ env: {}, cwd: '/proj', readConfig: () => null });
    expect(r.dir).toBe('/proj/wiki'); expect(r.mode).toBe('default');
  });
  it('3b) 미등록 vault 이름 → 폴백 + ok=false', () => {
    const r = resolveVault({ env: { LLM_OBSIDIAN_VAULT_NAME: 'nope' }, cwd: '/proj', readConfig: cfg });
    expect(r.dir).toBe('/proj/wiki'); expect(r.ok).toBe(false);
  });
});
```

- [ ] **Step 2: 실패 확인** — Run: `npx vitest run lib/wiki/vault_resolve.test.mjs` → FAIL (module not found).

- [ ] **Step 3: 최소 구현**

```js
// lib/wiki/vault_resolve.mjs
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';

export function obsidianConfigPaths(home = os.homedir()) {
  const p = [
    path.join(home, 'Library/Application Support/obsidian/obsidian.json'), // macOS
    path.join(home, '.config/obsidian/obsidian.json'),                     // Linux
  ];
  if (process.env.APPDATA) p.push(path.join(process.env.APPDATA, 'obsidian/obsidian.json'));
  return p;
}

function defaultReadConfig(paths) {
  for (const f of paths) { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch {} }
  return null;
}

export function resolveNamedVault(name, readConfig = defaultReadConfig) {
  const data = readConfig(obsidianConfigPaths());
  const vaults = data?.vaults; if (!vaults) return null;
  let best = null;
  for (const info of Object.values(vaults)) {
    if (!info || typeof info.path !== 'string') continue;
    if (path.basename(info.path) !== name) continue;
    const rank = [info.open ? 1 : 0, Number(info.ts) || 0];
    if (!best || rank[0] > best.rank[0] || (rank[0] === best.rank[0] && rank[1] > best.rank[1]))
      best = { path: info.path, rank };
  }
  return best ? best.path : null;
}

export function resolveVault({ env = process.env, cwd = process.cwd(), readConfig } = {}) {
  const rc = readConfig ? (() => readConfig()) : defaultReadConfig; // 테스트는 readConfig() 형태 주입
  const named = (n) => readConfig ? resolveNamedVaultWith(n, readConfig) : resolveNamedVault(n);
  if (env.WIKI_VAULT) return { dir: env.WIKI_VAULT, mode: 'explicit', ok: true };
  const name = env.LLM_OBSIDIAN_VAULT_NAME;
  if (name) {
    const base = named(name);
    if (base) return { dir: path.join(base, (env.LLM_WIKI_SUBDIR || 'LLM-Wiki').replace(/^\/+|\/+$/g, '')), mode: 'name', ok: true };
    return { dir: path.join(cwd, 'wiki'), mode: 'default', ok: false };
  }
  return { dir: path.join(cwd, 'wiki'), mode: 'default', ok: true };
}

function resolveNamedVaultWith(name, readConfig) {
  const data = readConfig(); const vaults = data?.vaults; if (!vaults) return null;
  let best = null;
  for (const info of Object.values(vaults)) {
    if (!info || typeof info.path !== 'string' || path.basename(info.path) !== name) continue;
    const rank = [info.open ? 1 : 0, Number(info.ts) || 0];
    if (!best || rank[0] > best.rank[0] || (rank[0] === best.rank[0] && rank[1] > best.rank[1])) best = { path: info.path, rank };
  }
  return best ? best.path : null;
}

// CLI: node lib/wiki/vault_resolve.mjs [--explain]
if (import.meta.url === `file://${process.argv[1]}`) {
  const r = resolveVault();
  if (process.argv.includes('--explain')) process.stdout.write(JSON.stringify(r, null, 2) + '\n');
  else process.stdout.write(r.dir + '\n');
}
```

- [ ] **Step 4: 통과 확인** — Run: `npx vitest run lib/wiki/vault_resolve.test.mjs` → PASS (5).

- [ ] **Step 5: 커밋** — `git add lib/wiki/vault_resolve.mjs lib/wiki/vault_resolve.test.mjs && git commit -m "feat(wiki): name-based Obsidian vault resolution"`

### Task 1.2: frontmatter 태깅 + type 확장

**Files:** Modify `lib/wiki/frontmatter.mjs`, `lib/wiki/frontmatter.test.mjs`

- [ ] **Step 1: 실패 테스트 추가** (frontmatter.test.mjs 에 append)

```js
import { ensureTags } from './frontmatter.mjs';
describe('tags', () => {
  it('ensureTags 가 ai-generated/llm-wiki/type 보장 + 기존 보존', () => {
    const out = ensureTags({ type: 'concept', tags: ['x'] });
    expect(out.tags).toEqual(expect.arrayContaining(['x', 'ai-generated', 'llm-wiki', 'concept']));
    expect(new Set(out.tags).size).toBe(out.tags.length); // 중복 없음
  });
  it('validate: tags 누락 → error', () => {
    const { tags, ...rest } = { ...fm }; expect(validateFrontmatter(rest).ok).toBe(false);
  });
  it('validate: type synthesis/ephemeral 허용', () => {
    expect(validateFrontmatter({ ...fm, type: 'synthesis', tags: ['ai-generated','llm-wiki','synthesis'] }).ok).toBe(true);
  });
});
```
(주의: 상단 `fm` 픽스처에 `tags: ['ai-generated','llm-wiki','concept']` 추가.)

- [ ] **Step 2: 실패 확인** — Run: `npx vitest run lib/wiki/frontmatter.test.mjs` → FAIL.

- [ ] **Step 3: 구현** (frontmatter.mjs)

```js
const REQUIRED_TAGS = ['ai-generated', 'llm-wiki'];
const TYPES = ['concept', 'entity', 'synthesis', 'ephemeral'];
export function ensureTags(fm) {
  const t = new Set([...(fm.tags ?? []), ...REQUIRED_TAGS]);
  if (fm.type) t.add(fm.type);
  return { ...fm, tags: [...t] };
}
```
그리고 `validateFrontmatter` 수정: `if (!TYPES.includes(fm?.type)) errors.push('type must be concept|entity|synthesis|ephemeral')`; 추가 `if (!Array.isArray(fm?.tags) || !REQUIRED_TAGS.every(x => fm.tags.includes(x))) errors.push('tags must include ai-generated, llm-wiki')`.

- [ ] **Step 4: 통과 확인** — Run: `npx vitest run lib/wiki/frontmatter.test.mjs` → PASS.

- [ ] **Step 5: 커밋** — `git commit -am "feat(wiki): require ai-generated/llm-wiki tags + synthesis/ephemeral types"`

### Task 1.3: apply.mjs 태그 주입

**Files:** Modify `lib/wiki/apply.mjs`, `lib/wiki/apply.test.mjs`

- [ ] **Step 1: 실패 테스트** — apply.test.mjs 에: ingest 한 페이지 파일을 parsePage 하면 `frontmatter.tags` 가 `ai-generated`,`llm-wiki`,`concept` 를 포함.
- [ ] **Step 2: 실패 확인** — `npx vitest run lib/wiki/apply.test.mjs` → FAIL.
- [ ] **Step 3: 구현** — apply.mjs 의 `fm` 생성(신규/머지) 직후 `const fmTagged = ensureTags(fm);` 로 감싸고 `validateFrontmatter(fmTagged)`·`serializePage({frontmatter: fmTagged,...})` 사용. 상단에 `import { ..., ensureTags } from './frontmatter.mjs';`. (type 가드 concept|entity 는 P1 유지.)
- [ ] **Step 4: 통과 확인** — `npx vitest run lib/wiki/apply.test.mjs` → PASS.
- [ ] **Step 5: 커밋** — `git commit -am "feat(wiki): stamp ai-generated tags on apply"`

### Task 1.4: 헌법(AGENTS.template) + index 콜아웃

**Files:** Modify `lib/wiki/AGENTS.template.md`, `lib/wiki/index_log.mjs`, `lib/wiki/index_log.test.mjs`

- [ ] **Step 1: 실패 테스트** (index_log.test.mjs): `rebuildIndex([])` 결과가 `🤖` 콜아웃 줄(`AI-generated`)을 포함.
- [ ] **Step 2: 실패 확인.**
- [ ] **Step 3: 구현** — `rebuildIndex` 의 머리글 배열을 `['# Wiki Index', '', '> [!info] 🤖 AI-generated — session-journal/research-engine 가 작성. `tag:#ai-generated` 로 필터.', '', ...]` 로. AGENTS.template.md 에 frontmatter `tags` 규칙 + `synthesis/`·`ephemeral/`·`_drafts/`(query/publish 제외) 설명 + promotion 규칙 + anti-AI 문체 한 단락 추가.
- [ ] **Step 4: 통과 확인.**
- [ ] **Step 5: 커밋** — `git commit -am "docs(wiki): tagging+temporal+promotion rules in constitution, AI-generated index callout"`

### Task 1.5: wiki.md 가 vault_resolve 사용 + 통합 테스트

**Files:** Modify `commands/wiki.md`, `tests/research-engine/wiki.test.sh`

- [ ] **Step 1: 통합 실패 테스트** — bats: 임시 HOME+가짜 obsidian.json(vault `harry`→tmp dir) + 픽스처 `research/<slug>/README.md`,`sources.json` 준비 → `LLM_OBSIDIAN_VAULT_NAME=harry` 로 ingest 절차의 부트스트랩+apply 실행 → `<harry>/LLM-Wiki/concepts/*.md` 가 생기고 `tags:` 에 `ai-generated` 포함.
- [ ] **Step 2: 실패 확인** — `bats tests/research-engine/wiki.test.sh` → FAIL.
- [ ] **Step 3: 구현** — `commands/wiki.md` 의 `## Constants` 에서 `VAULT = <project_cwd>/wiki` 를 `VAULT = $(node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/vault_resolve.mjs")` 로 교체, 부트스트랩에 `mkdir -p "${VAULT}/synthesis" "${VAULT}/ephemeral" "${VAULT}/_drafts" "${VAULT}/_todos"` 추가. 진단 한 줄: `node lib/wiki/vault_resolve.mjs --explain`.
- [ ] **Step 4: 통과 확인** — `bats tests/research-engine/wiki.test.sh` → PASS.
- [ ] **Step 5: 커밋** — `git commit -am "feat(wiki): resolve vault to Obsidian (harry/LLM-Wiki) in /wiki bootstrap"`

**Phase 1 완료 기준:** 어느 프로젝트에서 `/wiki ingest <slug>` → `harry/LLM-Wiki` 에 `#ai-generated` 태깅된 페이지 누적, Obsidian 이 그래프로 인식. `npx vitest run lib/wiki/ && bats tests/research-engine/wiki.test.sh` 전부 PASS.

---

## Phase 2 — Librarian: audit 확장 + 티어드 apply

**파일:** Modify `lib/wiki/lint.mjs`(+test) · Create `lib/wiki/librarian.mjs`(+test), `lib/wiki/changelog.mjs`(+test) · Modify `lib/wiki/apply.mjs`(`--draft`, DIR 확장) · Modify `commands/wiki.md`(`librarian` 액션).

**인터페이스 계약:**
- `lint.mjs`: `lintVault({ pages, now, researchSlugs })` 확장 — 추가 finding rule `stale`(updated < now-90d), `raw-coverage`(researchSlugs 중 log 미기재), `provenance`(sources 의 `research/<slug>` 가 researchSlugs 에 없음). 기존 rule 불변(회귀 테스트 유지).
- `changelog.mjs`: `appendChangeLog(text, {date, kind, detail})` → append-only 라인.
- `librarian.mjs`: `classify(findings)` → `{ auto: [...], draft: [...] }` (auto = broken-link/duplicate-name/stale-flag/tag-fix/coverage→todo; draft = new-page/new-link/synthesis/schema). `applyTier({vaultDir, plan, tier, budget})`.
- `apply.mjs`: `applyIngest({..., draft=false})` → draft 시 `_drafts/<DIR[type]>/`. `DIR` 에 `synthesis`,`ephemeral` 추가. type 가드/검증 TYPES 로 확장.

**핵심 테스트(수용기준):**
- stale: `updated`=100일전 → finding `stale`; 89일전 → 없음(`now` 주입).
- raw-coverage: researchSlugs=[a,b], log 에 a 만 → finding `raw-coverage: b`.
- provenance: sources=['research/ghost'] 인데 researchSlugs 에 없음 → finding.
- classify: 혼합 findings → auto/draft 정확 분리(스냅샷).
- apply `--draft`: 페이지가 `_drafts/concepts/<slug>.md` 에만 생성, `index.md` 미변경.
- librarian 통합(bats): 픽스처 vault → `node librarian.mjs --vault <v> --apply --budget 50` → 안전건 적용 + `change_log.md` 갱신 + `outputs/librarian-<date>.md` 리포트 + 위험건 `_drafts/`.

**commands/wiki.md `librarian` 액션 절차(에이전트):** 부트스트랩 → `librarian.mjs` audit → auto tier 자동 적용(결과 change_log) → draft tier 는 `_drafts/`+리포트 → 한글 요약 보고. `--report` 면 적용 없이 리포트만.

**완료 기준:** `/wiki librarian --apply` 가 안전 수정 자동 적용·위험 산출 draft 격리, 전 테스트 PASS.

---

## Phase 3 — Promote: `_drafts/` → live

**파일:** Create `lib/wiki/promote.mjs`(+test) · Modify `commands/wiki.md`(`promote` 액션).

**인터페이스:** `promote({vaultDir, slugs|all, date})` → `_drafts/<dir>/<slug>.md` 를 live `<dir>/` 로 이동(기존 페이지면 applyIngest 머지 경로 재사용), `index.md`/`log.md`/`change_log.md` 갱신. 멱등(재호출 시 no-op). 반환 `{promoted, skipped}`.

**핵심 테스트:**
- draft 1개 → promote → live 에 존재, `_drafts/` 에서 제거, index 에 등장.
- 재호출 멱등(promoted=0).
- `commands/wiki.md` `promote --critic`: critic 에이전트가 소스 대조 후 reject 한 slug 는 `_drafts/` 유지(통합/모킹).

**완료 기준:** draft 검토→승격 라운드트립 동작, 전 테스트 PASS.

---

## Phase 4 — dream / evolve (wiki 모드)

**파일:** Modify `commands/dream.md`(`--target=wiki`), `commands/evolve.md`(wiki region) · 필요한 `scripts/dream_run.sh`/`evolve_run.sh` 인자 확장 · `_index/reflect_state.json`·`evolve-ledger.json` 사용.

**dream(wiki):** 입력 코퍼스 = `VAULT` 의 concepts/entities(요약). 2단계 discovery→synthesis. 산출: `_drafts/synthesis/<slug>.md`(type synthesis, 근거 페이지 2+ slug 인용, 태깅) + `_todos/<topic>.md`(gap 리서치 질문). 증분 `_index/reflect_state.json`. **synthesis 는 항상 draft**(P3 promote 대상).

**evolve(wiki):** evolvable region = `AGENTS.md` 의 명시 구역/librarian 휴리스틱. prompt-mutator 로 변형 후보 → `_drafts/_schema/agents-<region>.candidate.md` + `_index/evolve-ledger.json`. 스키마 변경은 항상 draft.

**핵심 테스트(통합/모킹):**
- dream --target=wiki: 픽스처 위키 → `_drafts/synthesis/*.md` + `_todos/*.md` 생성, reflect_state 증분.
- evolve wiki: candidate 파일 + ledger 항목 생성, live AGENTS.md 미변경.

**완료 기준:** dream/evolve 가 위키에 적용돼 draft 산출, 전 테스트 PASS.

---

## Phase 5 — Publish 제외 + Trigger + Release

**파일:** Modify `scripts/wiki_publish.sh` · Create `scripts/wiki_librarian_cron.sh` · Modify `README.md`,`CHANGELOG.md`,`.claude-plugin/plugin.json`.

- `wiki_publish.sh`: content 복사에서 `_drafts/_todos/_index/ephemeral` 제외, `synthesis/` 포함. smoke 유지.
- `wiki_librarian_cron.sh`: `claude -p "/wiki librarian --apply --budget ${WIKI_LIBRARIAN_BUDGET:-50}"` 래퍼(headless). 문서에 월간 등록 예시 — `schedule` 스킬 또는 cron(`0 3 1 * *`) / hetzner cron.
- README: `/wiki librarian|promote|dream --target=wiki|evolve` + vault env(`LLM_OBSIDIAN_VAULT_NAME`,`LLM_WIKI_SUBDIR`,`WIKI_VAULT`) 문서.
- CHANGELOG + `version` 0.17.0 → **0.18.0**.

**완료 기준:** publish 가 검증분만 발행, 월간 cron 래퍼 동작(dry-run), 문서/버전 동기화. `npx vitest run lib/wiki/ && bats tests/research-engine/wiki.test.sh` 전부 PASS → `git push` + (선택) 마켓플레이스 반영.

---

## Self-Review (작성자 체크)

- **Spec 커버리지**: D1(P1 vault_resolve)·D2(P1 harry/LLM-Wiki)·D3(P4 dream/evolve)·D4(P2 티어드+P3 promote)·D5(P5 cron) / 태깅(P1)·temporal(P1 폴더+P2 stale)·promotion gate(P2 draft+P3)·리스크 컨트롤(budget P2, critic P3, git audit 기존) 전부 매핑됨. ephemeral 만료 실제 정책은 spec §13 대로 후속(미할당 — 의도적 비범위).
- **Placeholder**: P1 은 실코드/실명령. P2~P5 는 인터페이스·테스트·수용기준 명시(코드는 P1 산출 의존이라 실행 진입 시 동일 TDD 로 전개 — codex 워커 단위).
- **타입 일관성**: `resolveVault`/`ensureTags`/`applyIngest(draft)`/`lintVault({pages,now,researchSlugs})`/`promote()` 시그니처 Phase 간 일치. `DIR` 확장(concept|entity|synthesis|ephemeral)이 frontmatter TYPES·apply 가드와 일치(P1 validate 확장 → P2 apply 가드 확장 순서 주의).
