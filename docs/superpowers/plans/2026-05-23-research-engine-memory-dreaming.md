# research-engine Memory & Dreaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** research-engine에 cross-session learning(Memory + Dreaming)을 도입한다. `/research`가 과거 유사 세션과 dream 인사이트를 어댑터 dispatch에 자동 주입하고, 5회 누적 시 `/dream` 호출을 제안. 사용자가 `/dream`을 명시 호출하면 과거 세션들에서 반복 패턴·어댑터 실패·자주 묻는 의도를 추출해 `docs/dreams/<run-id>/`에 readonly 인사이트로 누적.

**Architecture:** `research/_index/` (manifest + dream-ledger) = derivable readonly 인덱스. `docs/dreams/<run-id>/` = 사람-편집 가능한 인사이트 artifact (편집/삭제 = adopt 결정). `/research` Stage 2(prior query)/5.2(hash·actor 기록)/5.8(ledger update + 제안)/4(dispatch에 prior 주입) hook + `/research-followup` OCC + `/bench` post-hook 제안 + 새 `/dream` 슬래시. dream 출력은 기존 Agent subagent dispatch 패턴 재사용 — 새 LLM 호출 인프라 도입 없음.

**Tech Stack:** Node.js (ESM, vitest) for `lib/memory/`, bash + jq for scripts, bats for integration/e2e. 기존 `slugify.sh`·`push_to_notion.sh`·mock claude CLI 재사용. SHA256는 `node:crypto`(JS)·`sha256sum`(shell) 둘 다 사용. 자식 프로세스는 항상 `execFileSync` (shell 비활성화, 인젝션 방지). 신규 npm 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-05-23-research-engine-memory-dreaming-design.md` (commit `0e2afc6`)

---

## File Structure

**Create (신규 파일):**

*lib/memory/ — Node ESM 유틸:*
- `lib/memory/tokenize.mjs` — intent.purpose 한·영 토크나이즈
- `lib/memory/tokenize.test.mjs` — vitest unit
- `lib/memory/similarity.mjs` — input_type/topics/purpose_tokens 가중합
- `lib/memory/similarity.test.mjs` — vitest unit
- `lib/memory/manifest_schema.mjs` — sessions·dreams entry 빌더 + `--build` CLI
- `lib/memory/manifest_schema.test.mjs` — vitest unit
- `lib/memory/ledger.mjs` — 카운터 상태기계 + `--rebuild`/`--bump`/`--reset` CLI
- `lib/memory/ledger.test.mjs` — vitest unit

*scripts/ — shell orchestration:*
- `scripts/memory_reindex.sh` — manifest 재생성, idempotent + atomic rename + ledger rebuild
- `scripts/memory_query.sh` — manifest 읽고 top-K prior + active dreams JSON 반환, fail-soft
- `scripts/dream_run.sh` — D1·D2·D4~D7 shell 래퍼 (D3 dispatch는 commands/dream.md 슬래시)

*commands/ + agents/ — 슬래시·페르소나:*
- `commands/dream.md` — `/dream` 슬래시 진입 + D1~D8 시퀀스
- `agents/dream-extractor.md` — dream agent persona (어댑터 페르소나 패턴 차용)

*tests/research-engine/ — bats + fixtures:*
- `tests/research-engine/memory.test.sh` — bats (reindex / query 입출력 계약)
- `tests/research-engine/dream.test.sh` — bats (dream_run.sh 인자 처리·실패 모드)
- `tests/research-engine/research-with-memory.test.sh` — bats e2e (prior_knowledge 주입)
- `tests/research-engine/dream-e2e.test.sh` — bats e2e (풀 사이클 + status 편집)
- `tests/research-engine/research-followup-occ.test.sh` — bats (OCC sha256)
- `tests/research-engine/fixtures/memory/manifest-empty/` — 빈 research/ + 빈 dreams/
- `tests/research-engine/fixtures/memory/manifest-3-sessions/` — 가짜 세션 3개
- `tests/research-engine/fixtures/memory/legacy-no-hash/` — content_sha256 없는 기존 세션 fixture
- `tests/research-engine/fixtures/dream-input-sessions/` — /dream 입력용 3개 세션
- `tests/research-engine/fixtures/dreams/active/README.md` — status=active dream fixture
- `tests/research-engine/fixtures/dreams/discarded/README.md` — status=discarded dream fixture

**Modify (기존 파일 수정):**
- `commands/research.md` — Stage 2 prior query hook · Stage 5.2 sources.json hash·actor · Stage 4 prior_knowledge 주입 · Stage 5.8 ledger update + 제안
- `commands/research-followup.md` — session.md write 직전 sha256 OCC precondition (1회 자동 재시도)
- `commands/bench.md` — post-hook 제안 1줄
- `package.json` — `test:bats`에 새 bats 파일 5개 추가

**Security convention:** Node child process는 항상 `node:child_process.execFileSync('cmd', ['arg1', 'arg2'], opts)` 형태로 호출 — shell 비활성화 + 인자 분리로 인젝션 방지. `exec`/`execSync` (shell 형태)는 사용하지 않는다.

**No delete / rename.**

---

## Task 1: tokenize — 한·영 토크나이저 (RED → GREEN → COMMIT)

**Files:**
- Create: `lib/memory/tokenize.mjs`
- Create: `lib/memory/tokenize.test.mjs`

- [ ] **Step 1: 실패 테스트 작성**

`lib/memory/tokenize.test.mjs`:

```javascript
import { describe, it, expect } from 'vitest';
import { tokenize } from './tokenize.mjs';

describe('tokenize', () => {
  it('영문 단어를 소문자로 분리한다', () => {
    expect(tokenize('Memory and Dreaming for Self-Learning Agents')).toEqual(
      ['memory', 'and', 'dreaming', 'for', 'self', 'learning', 'agents']
    );
  });

  it('한글 어절을 그대로 분리한다', () => {
    expect(tokenize('에이전트 메모리 시스템')).toEqual(
      ['에이전트', '메모리', '시스템']
    );
  });

  it('한·영 혼합 입력을 모두 처리한다', () => {
    expect(tokenize('Anthropic Memory & 드리밍 설계')).toEqual(
      ['anthropic', 'memory', '드리밍', '설계']
    );
  });

  it('영문 길이 2 미만 토큰을 제외하고, 한글은 보존한다', () => {
    expect(tokenize('AI a b 한 글')).toEqual(['ai', '한', '글']);
  });

  it('NFC 정규화로 같은 결과를 만든다', () => {
    const composed = '한글';
    const decomposed = '한글'.normalize('NFD');
    expect(tokenize(composed)).toEqual(tokenize(decomposed));
  });

  it('null/undefined/빈 문자열에 빈 배열을 반환한다', () => {
    expect(tokenize(null)).toEqual([]);
    expect(tokenize(undefined)).toEqual([]);
    expect(tokenize('')).toEqual([]);
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

```
npx vitest run lib/memory/tokenize.test.mjs
```

Expected: FAIL — `Cannot find module './tokenize.mjs'`.

- [ ] **Step 3: 최소 구현**

`lib/memory/tokenize.mjs`:

```javascript
export function tokenize(input) {
  if (input == null) return [];
  const text = String(input).normalize('NFC');
  const matches = [];
  for (const m of text.matchAll(/[가-힣]+|[a-zA-Z]+/g)) {
    matches.push({ token: m[0], offset: m.index, isHangul: /[가-힣]/.test(m[0]) });
  }
  return matches
    .filter(m => m.isHangul || m.token.length >= 2)
    .map(m => m.isHangul ? m.token : m.token.toLowerCase());
}
```

- [ ] **Step 4: 테스트 통과 확인**

```
npx vitest run lib/memory/tokenize.test.mjs
```

Expected: PASS — 6/6.

- [ ] **Step 5: Commit**

```bash
git add lib/memory/tokenize.mjs lib/memory/tokenize.test.mjs
git commit -m "feat(memory): tokenize — 한·영 NFC 토크나이저 + vitest unit"
```

---

## Task 2: similarity — 가중합 매처 (RED → GREEN → COMMIT)

**Files:**
- Create: `lib/memory/similarity.mjs`
- Create: `lib/memory/similarity.test.mjs`

- [ ] **Step 1: 실패 테스트 작성**

`lib/memory/similarity.test.mjs`:

```javascript
import { describe, it, expect } from 'vitest';
import { scoreSession, topK } from './similarity.mjs';

const target = {
  input_type: 'youtube',
  topics: ['agent memory', 'dreaming', 'managed agents'],
  intent: { purpose_tokens: ['memory', 'dreaming', 'research', 'engine'] }
};

describe('scoreSession', () => {
  it('input_type 동치 시 가중치 3 적용', () => {
    const c = { input_type: 'youtube', topics: [], intent: { purpose_tokens: [] } };
    expect(scoreSession(target, c)).toBe(3);
  });

  it('input_type 불일치 시 그 항목은 0', () => {
    const c = { input_type: 'arxiv', topics: [], intent: { purpose_tokens: [] } };
    expect(scoreSession(target, c)).toBe(0);
  });

  it('topics 교집합 수에 가중치 2', () => {
    const c = { input_type: 'arxiv', topics: ['agent memory', 'dreaming', 'unrelated'], intent: { purpose_tokens: [] } };
    expect(scoreSession(target, c)).toBe(4);
  });

  it('purpose_tokens 교집합 수에 가중치 1', () => {
    const c = { input_type: 'arxiv', topics: [], intent: { purpose_tokens: ['memory', 'research', 'unrelated'] } };
    expect(scoreSession(target, c)).toBe(2);
  });

  it('세 가중치 합산', () => {
    const c = {
      input_type: 'youtube',
      topics: ['agent memory', 'dreaming'],
      intent: { purpose_tokens: ['memory', 'research'] }
    };
    expect(scoreSession(target, c)).toBe(3 + 4 + 2);
  });
});

describe('topK', () => {
  const candidates = [
    { slug: 'a', input_type: 'youtube', topics: ['agent memory'], intent: { purpose_tokens: [] }, created: '2026-05-01' },
    { slug: 'b', input_type: 'arxiv', topics: [], intent: { purpose_tokens: ['memory'] }, created: '2026-05-02' },
    { slug: 'c', input_type: 'youtube', topics: ['agent memory', 'dreaming'], intent: { purpose_tokens: ['memory'] }, created: '2026-05-03' },
    { slug: 'd', input_type: 'blog', topics: ['unrelated'], intent: { purpose_tokens: [] }, created: '2026-05-04' }
  ];

  it('가장 점수 높은 K개 반환', () => {
    const res = topK(target, candidates, 2);
    expect(res.map(r => r.slug)).toEqual(['c', 'a']);
  });

  it('점수 0인 후보는 제외 (d 제외)', () => {
    const res = topK(target, candidates, 10);
    expect(res.map(r => r.slug)).toEqual(['c', 'a', 'b']);
  });

  it('K가 후보 수보다 크면 가능한 만큼만', () => {
    const res = topK(target, candidates, 100);
    expect(res.length).toBe(3);
  });

  it('동점 시 created desc 안정 정렬', () => {
    const ties = [
      { slug: 't1', input_type: 'youtube', topics: [], intent: { purpose_tokens: [] }, created: '2026-05-01' },
      { slug: 't2', input_type: 'youtube', topics: [], intent: { purpose_tokens: [] }, created: '2026-05-02' }
    ];
    const res = topK(target, ties, 2);
    expect(res.map(r => r.slug)).toEqual(['t2', 't1']);
  });

  it('target.slug과 같은 후보 self-exclusion', () => {
    const t = { ...target, slug: 'c' };
    const res = topK(t, candidates, 10);
    expect(res.map(r => r.slug)).not.toContain('c');
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

```
npx vitest run lib/memory/similarity.test.mjs
```

Expected: FAIL.

- [ ] **Step 3: 최소 구현**

`lib/memory/similarity.mjs`:

```javascript
const W_TYPE = 3;
const W_TOPIC = 2;
const W_PURPOSE = 1;

function intersectionCount(a, b) {
  const setB = new Set(b);
  let count = 0;
  for (const x of a) if (setB.has(x)) count++;
  return count;
}

export function scoreSession(target, candidate) {
  let score = 0;
  if (target.input_type && candidate.input_type === target.input_type) score += W_TYPE;
  score += intersectionCount(target.topics ?? [], candidate.topics ?? []) * W_TOPIC;
  score += intersectionCount(
    target.intent?.purpose_tokens ?? [],
    candidate.intent?.purpose_tokens ?? []
  ) * W_PURPOSE;
  return score;
}

export function topK(target, candidates, k) {
  const scored = candidates
    .filter(c => target.slug == null || c.slug !== target.slug)
    .map(c => ({ ...c, _score: scoreSession(target, c) }))
    .filter(c => c._score > 0);
  scored.sort((a, b) => {
    if (b._score !== a._score) return b._score - a._score;
    return String(b.created ?? '').localeCompare(String(a.created ?? ''));
  });
  return scored.slice(0, k);
}
```

- [ ] **Step 4: 테스트 통과 확인**

```
npx vitest run lib/memory/similarity.test.mjs
```

Expected: PASS — 9/9.

- [ ] **Step 5: Commit**

```bash
git add lib/memory/similarity.mjs lib/memory/similarity.test.mjs
git commit -m "feat(memory): similarity — input_type·topics·purpose_tokens 가중합 매처"
```

---

## Task 3: manifest_schema — entry builder + --build CLI (RED → GREEN → COMMIT)

**Files:**
- Create: `lib/memory/manifest_schema.mjs`
- Create: `lib/memory/manifest_schema.test.mjs`
- Create: `tests/research-engine/fixtures/memory/legacy-no-hash/research/2026-04-01-legacy-fixture/{README.md,sources.json,intent.json}`
- Create: `tests/research-engine/fixtures/memory/manifest-empty/research/.gitkeep`
- Create: `tests/research-engine/fixtures/memory/manifest-empty/docs/dreams/.gitkeep`

- [ ] **Step 1: 두 fixture 세트 생성**

```bash
mkdir -p tests/research-engine/fixtures/memory/legacy-no-hash/research/2026-04-01-legacy-fixture
mkdir -p tests/research-engine/fixtures/memory/manifest-empty/research
mkdir -p tests/research-engine/fixtures/memory/manifest-empty/docs/dreams
touch tests/research-engine/fixtures/memory/manifest-empty/research/.gitkeep
touch tests/research-engine/fixtures/memory/manifest-empty/docs/dreams/.gitkeep
```

`tests/research-engine/fixtures/memory/legacy-no-hash/research/2026-04-01-legacy-fixture/README.md`:

```markdown
---
title: "Legacy fixture"
slug: "2026-04-01-legacy-fixture"
input_type: "youtube"
created: "2026-04-01T10:00:00+09:00"
---

# Legacy fixture body

## 핵심 포인트

- youtube caption parsing pattern
```

`tests/research-engine/fixtures/memory/legacy-no-hash/research/2026-04-01-legacy-fixture/sources.json`:

```json
{
  "input": "https://youtu.be/legacy",
  "input_type": "youtube",
  "intent": {
    "purpose": "테스트 목적",
    "focus": "legacy fixture",
    "audience_level": "테스트"
  },
  "created": "2026-04-01T10:00:00+09:00",
  "sources": [
    { "n": 1, "adapter": "youtube", "type": "youtube-captions", "url": "https://youtu.be/legacy", "title": "Legacy" }
  ]
}
```

`tests/research-engine/fixtures/memory/legacy-no-hash/research/2026-04-01-legacy-fixture/intent.json`:

```json
{
  "purpose": "테스트 목적",
  "focus": "legacy fixture",
  "audience_level": "테스트",
  "intent_mode": "user"
}
```

- [ ] **Step 2: 실패 테스트 작성**

`lib/memory/manifest_schema.test.mjs`:

```javascript
import { describe, it, expect } from 'vitest';
import { buildSessionEntry, buildDreamEntry, buildManifest } from './manifest_schema.mjs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtureBase = path.resolve(__dirname, '..', '..', 'tests', 'research-engine', 'fixtures', 'memory');

describe('buildSessionEntry', () => {
  it('legacy 세션(content_sha256 부재)을 derived 모드로 빌드', async () => {
    const sessionPath = path.join(fixtureBase, 'legacy-no-hash', 'research', '2026-04-01-legacy-fixture');
    const entry = await buildSessionEntry(sessionPath);

    expect(entry.slug).toBe('2026-04-01-legacy-fixture');
    expect(entry.input_type).toBe('youtube');
    expect(entry.content_sha256).toMatch(/^[0-9a-f]{64}$/);
    expect(entry.created_by).toEqual([]);
    expect(entry.intent.purpose_tokens).toContain('테스트');
    expect(entry.sources_summary.count).toBe(1);
    expect(entry.sources_summary.by_type['youtube-captions']).toBe(1);
    expect(entry.dreamed_in).toEqual([]);
  });
});

describe('buildDreamEntry', () => {
  it('존재하지 않는 dream 경로 → reject', async () => {
    const dreamPath = path.join(fixtureBase, 'no-such-dream');
    await expect(buildDreamEntry(dreamPath)).rejects.toThrow();
  });
});

describe('buildManifest', () => {
  it('빈 research/ + 빈 dreams/ → 빈 sessions·dreams', async () => {
    const researchDir = path.join(fixtureBase, 'manifest-empty', 'research');
    const dreamsDir = path.join(fixtureBase, 'manifest-empty', 'docs', 'dreams');
    const manifest = await buildManifest({ researchDir, dreamsDir });

    expect(manifest.version).toBe(1);
    expect(manifest.sessions).toEqual([]);
    expect(manifest.dreams).toEqual([]);
    expect(manifest.generator).toMatch(/memory_reindex\.sh/);
  });

  it('legacy fixture → 1 session, 0 dream', async () => {
    const researchDir = path.join(fixtureBase, 'legacy-no-hash', 'research');
    const dreamsDir = path.join(fixtureBase, 'manifest-empty', 'docs', 'dreams');
    const manifest = await buildManifest({ researchDir, dreamsDir });
    expect(manifest.sessions.length).toBe(1);
    expect(manifest.dreams.length).toBe(0);
  });
});
```

- [ ] **Step 3: 테스트 실패 확인**

```
npx vitest run lib/memory/manifest_schema.test.mjs
```

Expected: FAIL — `Cannot find module './manifest_schema.mjs'`.

- [ ] **Step 4: 최소 구현 (execFileSync 사용)**

`lib/memory/manifest_schema.mjs`:

```javascript
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { tokenize } from './tokenize.mjs';

async function readJsonOrNull(filePath) {
  try {
    return JSON.parse(await fs.readFile(filePath, 'utf8'));
  } catch {
    return null;
  }
}

async function readFrontmatter(mdPath) {
  try {
    const text = await fs.readFile(mdPath, 'utf8');
    const m = text.match(/^---\n([\s\S]*?)\n---/);
    if (!m) return {};
    const fm = {};
    for (const line of m[1].split('\n')) {
      const kv = line.match(/^(\w+):\s*"?(.*?)"?$/);
      if (kv) fm[kv[1]] = kv[2];
    }
    return fm;
  } catch {
    return {};
  }
}

function extractTopics(readmeText) {
  const topicCandidates = new Set();
  for (const m of readmeText.matchAll(/^###?\s+(.+?)$/gm)) {
    const cleaned = m[1].replace(/\(.*?\)|\[.*?\]|—|—.*$/g, '').trim();
    if (cleaned.length >= 2 && cleaned.length <= 60) topicCandidates.add(cleaned);
  }
  return Array.from(topicCandidates).slice(0, 12);
}

export async function buildSessionEntry(sessionPath) {
  const slug = path.basename(sessionPath);
  const readmePath = path.join(sessionPath, 'README.md');
  const sourcesPath = path.join(sessionPath, 'sources.json');
  const intentPath = path.join(sessionPath, 'intent.json');

  const [sources, intent, fm] = await Promise.all([
    readJsonOrNull(sourcesPath),
    readJsonOrNull(intentPath),
    readFrontmatter(readmePath)
  ]);

  let readmeText = '';
  try { readmeText = await fs.readFile(readmePath, 'utf8'); } catch {}

  const explicitHash = sources?.content_sha256;
  const content_sha256 = explicitHash ?? (readmeText
    ? crypto.createHash('sha256').update(readmeText).digest('hex')
    : '');

  const explicitActors = sources?.created_by;
  const created_by = Array.isArray(explicitActors) ? explicitActors : [];

  const purpose = intent?.purpose ?? sources?.intent?.purpose ?? '';
  const focus = intent?.focus ?? sources?.intent?.focus ?? '';
  const audience_level = intent?.audience_level ?? sources?.intent?.audience_level ?? '';

  const bySources = sources?.sources ?? [];
  const by_type = {};
  for (const s of bySources) {
    const t = s.type ?? 'unknown';
    by_type[t] = (by_type[t] ?? 0) + 1;
  }

  return {
    slug,
    path: path.relative(process.cwd(), sessionPath),
    input_type: sources?.input_type ?? fm.input_type ?? 'unknown',
    input: sources?.input ?? '',
    title: fm.title ?? '',
    created: sources?.created ?? fm.created ?? '',
    intent: {
      purpose,
      focus,
      audience_level,
      purpose_tokens: tokenize(`${purpose} ${focus}`)
    },
    sources_summary: { count: bySources.length, by_type },
    topics: extractTopics(readmeText),
    related_count: 0,
    content_sha256,
    created_by,
    notion_url: sources?.output_notion_url ?? '',
    dreamed_in: []
  };
}

export async function buildDreamEntry(dreamPath) {
  const run_id = path.basename(dreamPath);
  const readmePath = path.join(dreamPath, 'README.md');
  await fs.readFile(readmePath, 'utf8');  // throws if missing
  const fm = await readFrontmatter(readmePath);
  let insight_files = [];
  try {
    insight_files = (await fs.readdir(path.join(dreamPath, 'insights')))
      .filter(f => f.endsWith('.md'));
  } catch {}
  return {
    run_id,
    path: path.relative(process.cwd(), dreamPath),
    created: fm.created ?? '',
    status: fm.status ?? 'active',
    supersedes: fm.supersedes && fm.supersedes !== 'null' ? fm.supersedes : null,
    inputs: [],
    insight_files
  };
}

function getGitSha() {
  try {
    return execFileSync('git', ['rev-parse', '--short', 'HEAD'], { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
  } catch {
    return 'unknown';
  }
}

export async function buildManifest({ researchDir, dreamsDir }) {
  const sessions = [];
  const dreams = [];

  try {
    const entries = await fs.readdir(researchDir, { withFileTypes: true });
    for (const e of entries) {
      if (!e.isDirectory() || e.name.startsWith('_')) continue;
      const sessionPath = path.join(researchDir, e.name);
      try {
        const entry = await buildSessionEntry(sessionPath);
        try {
          const rels = await fs.readdir(path.join(sessionPath, 'related'));
          entry.related_count = rels.filter(r => r.endsWith('.md')).length;
        } catch {}
        sessions.push(entry);
      } catch {}
    }
  } catch {}

  try {
    const entries = await fs.readdir(dreamsDir, { withFileTypes: true });
    for (const e of entries) {
      if (!e.isDirectory()) continue;
      const dreamPath = path.join(dreamsDir, e.name);
      try {
        const entry = await buildDreamEntry(dreamPath);
        const drSources = await readJsonOrNull(path.join(dreamPath, 'sources.json'));
        if (drSources?.inputs) entry.inputs = drSources.inputs;
        dreams.push(entry);
        for (const inputSlug of entry.inputs ?? []) {
          const session = sessions.find(s => s.slug === inputSlug);
          if (session && !session.dreamed_in.includes(entry.run_id)) {
            session.dreamed_in.push(entry.run_id);
          }
        }
      } catch {}
    }
  } catch {}

  return {
    version: 1,
    generated_at: new Date().toISOString(),
    generator: `scripts/memory_reindex.sh@${getGitSha()}`,
    sessions,
    dreams
  };
}

// CLI: node manifest_schema.mjs --build --research-dir <path> --dreams-dir <path>
if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  if (args[0] === '--build') {
    const get = (flag) => {
      const i = args.indexOf(flag);
      return i >= 0 ? args[i + 1] : null;
    };
    const manifest = await buildManifest({
      researchDir: get('--research-dir') ?? 'research',
      dreamsDir: get('--dreams-dir') ?? 'docs/dreams'
    });
    process.stdout.write(JSON.stringify(manifest, null, 2) + '\n');
  } else {
    console.error('usage: node manifest_schema.mjs --build --research-dir <path> --dreams-dir <path>');
    process.exit(2);
  }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```
npx vitest run lib/memory/manifest_schema.test.mjs
```

Expected: PASS — 4/4.

- [ ] **Step 6: CLI smoke test**

```bash
node lib/memory/manifest_schema.mjs --build \
  --research-dir tests/research-engine/fixtures/memory/legacy-no-hash/research \
  --dreams-dir tests/research-engine/fixtures/memory/manifest-empty/docs/dreams \
  | jq '.sessions | length'
```

Expected: `1`.

- [ ] **Step 7: Commit**

```bash
git add lib/memory/manifest_schema.mjs lib/memory/manifest_schema.test.mjs \
       tests/research-engine/fixtures/memory/legacy-no-hash \
       tests/research-engine/fixtures/memory/manifest-empty
git commit -m "feat(memory): manifest_schema — buildSessionEntry/buildDreamEntry/buildManifest + --build CLI"
```

---

## Task 4: ledger — 카운터 상태기계 + CLI (RED → GREEN → COMMIT)

**Files:**
- Create: `lib/memory/ledger.mjs`
- Create: `lib/memory/ledger.test.mjs`

- [ ] **Step 1: 실패 테스트 작성**

`lib/memory/ledger.test.mjs`:

```javascript
import { describe, it, expect } from 'vitest';
import {
  emptyLedger,
  bumpAfterResearch,
  shouldSuggest,
  markSuggested,
  resetAfterDream,
  rebuildFromManifest
} from './ledger.mjs';

describe('emptyLedger', () => {
  it('초기 상태는 null + 빈 배열', () => {
    expect(emptyLedger()).toEqual({
      version: 1,
      last_dream_run_id: null,
      last_dream_at: null,
      sessions_since_last_dream: [],
      suggestion_threshold: 5,
      suggestion_shown_at: null,
      last_shown_count: 0
    });
  });
});

describe('bumpAfterResearch', () => {
  it('새 슬러그를 카운터에 추가', () => {
    const next = bumpAfterResearch(emptyLedger(), 'new-slug');
    expect(next.sessions_since_last_dream).toEqual(['new-slug']);
  });

  it('중복 슬러그는 추가하지 않음', () => {
    const l = bumpAfterResearch(emptyLedger(), 's1');
    const next = bumpAfterResearch(l, 's1');
    expect(next.sessions_since_last_dream).toEqual(['s1']);
  });
});

describe('shouldSuggest', () => {
  it('카운터 < threshold이면 false', () => {
    const l = { ...emptyLedger(), sessions_since_last_dream: ['a', 'b', 'c', 'd'] };
    expect(shouldSuggest(l)).toBe(false);
  });

  it('카운터 == threshold이고 suggestion 미노출이면 true', () => {
    const l = { ...emptyLedger(), sessions_since_last_dream: ['a', 'b', 'c', 'd', 'e'] };
    expect(shouldSuggest(l)).toBe(true);
  });

  it('카운터 6 — 이미 5에서 보여줬다면 false', () => {
    const l = {
      ...emptyLedger(),
      sessions_since_last_dream: ['a', 'b', 'c', 'd', 'e', 'f'],
      suggestion_shown_at: '2026-05-23T00:00:00+09:00',
      last_shown_count: 5
    };
    expect(shouldSuggest(l)).toBe(false);
  });

  it('카운터 10 — 5에서 보여준 뒤 +5 누적 시 true', () => {
    const l = {
      ...emptyLedger(),
      sessions_since_last_dream: Array.from({ length: 10 }, (_, i) => `s${i}`),
      suggestion_shown_at: '2026-05-23T00:00:00+09:00',
      last_shown_count: 5
    };
    expect(shouldSuggest(l)).toBe(true);
  });

  it('threshold 사용자 변경 (3)', () => {
    const l = { ...emptyLedger(), suggestion_threshold: 3, sessions_since_last_dream: ['a', 'b', 'c'] };
    expect(shouldSuggest(l)).toBe(true);
  });
});

describe('markSuggested + resetAfterDream', () => {
  it('markSuggested는 last_shown_count와 timestamp 갱신', () => {
    const l = { ...emptyLedger(), sessions_since_last_dream: ['a', 'b', 'c', 'd', 'e'] };
    const next = markSuggested(l, '2026-05-23T00:00:00+09:00');
    expect(next.suggestion_shown_at).toBe('2026-05-23T00:00:00+09:00');
    expect(next.last_shown_count).toBe(5);
  });

  it('resetAfterDream은 모든 상태 초기화', () => {
    const l = {
      ...emptyLedger(),
      sessions_since_last_dream: ['a', 'b', 'c', 'd', 'e'],
      suggestion_shown_at: '2026-05-23T00:00:00+09:00',
      last_shown_count: 5
    };
    const next = resetAfterDream(l, 'drm_2026-06-01', '2026-06-01T10:00:00+09:00');
    expect(next.sessions_since_last_dream).toEqual([]);
    expect(next.last_dream_run_id).toBe('drm_2026-06-01');
    expect(next.last_dream_at).toBe('2026-06-01T10:00:00+09:00');
    expect(next.suggestion_shown_at).toBeNull();
    expect(next.last_shown_count).toBe(0);
  });
});

describe('rebuildFromManifest', () => {
  it('manifest sessions + dreams로부터 ledger 재구성', () => {
    const manifest = {
      sessions: [
        { slug: 's-old', created: '2026-04-01' },
        { slug: 's-after-1', created: '2026-05-15' },
        { slug: 's-after-2', created: '2026-05-20' }
      ],
      dreams: [{ run_id: 'drm_2026-05-10', created: '2026-05-10', status: 'active' }]
    };
    const l = rebuildFromManifest(manifest);
    expect(l.last_dream_run_id).toBe('drm_2026-05-10');
    expect(l.last_dream_at).toBe('2026-05-10');
    expect(l.sessions_since_last_dream).toEqual(['s-after-1', 's-after-2']);
  });

  it('dreams가 비어 있으면 모든 세션이 since', () => {
    const manifest = {
      sessions: [{ slug: 'a', created: '2026-01-01' }, { slug: 'b', created: '2026-02-01' }],
      dreams: []
    };
    const l = rebuildFromManifest(manifest);
    expect(l.last_dream_run_id).toBeNull();
    expect(l.sessions_since_last_dream).toEqual(['a', 'b']);
  });
});
```

- [ ] **Step 2: 테스트 실패 확인**

```
npx vitest run lib/memory/ledger.test.mjs
```

Expected: FAIL.

- [ ] **Step 3: 최소 구현**

`lib/memory/ledger.mjs`:

```javascript
import fs from 'node:fs/promises';

export function emptyLedger() {
  return {
    version: 1,
    last_dream_run_id: null,
    last_dream_at: null,
    sessions_since_last_dream: [],
    suggestion_threshold: 5,
    suggestion_shown_at: null,
    last_shown_count: 0
  };
}

export function bumpAfterResearch(ledger, slug) {
  if (ledger.sessions_since_last_dream.includes(slug)) return { ...ledger };
  return {
    ...ledger,
    sessions_since_last_dream: [...ledger.sessions_since_last_dream, slug]
  };
}

export function shouldSuggest(ledger) {
  const count = ledger.sessions_since_last_dream.length;
  if (count < ledger.suggestion_threshold) return false;
  if (ledger.suggestion_shown_at == null) return true;
  return count >= ledger.last_shown_count + ledger.suggestion_threshold;
}

export function markSuggested(ledger, nowIso) {
  return {
    ...ledger,
    suggestion_shown_at: nowIso,
    last_shown_count: ledger.sessions_since_last_dream.length
  };
}

export function resetAfterDream(ledger, runId, nowIso) {
  return {
    ...ledger,
    last_dream_run_id: runId,
    last_dream_at: nowIso,
    sessions_since_last_dream: [],
    suggestion_shown_at: null,
    last_shown_count: 0
  };
}

export function rebuildFromManifest(manifest) {
  const activeDreams = (manifest.dreams ?? []).filter(d => d.status === 'active');
  activeDreams.sort((a, b) => String(b.created ?? '').localeCompare(String(a.created ?? '')));
  const latestDream = activeDreams[0] ?? null;

  const sessions = manifest.sessions ?? [];
  const sinceCutoff = latestDream?.created ?? '';
  const sinceList = sessions
    .filter(s => !sinceCutoff || String(s.created ?? '').localeCompare(sinceCutoff) > 0)
    .map(s => s.slug);

  return {
    version: 1,
    last_dream_run_id: latestDream?.run_id ?? null,
    last_dream_at: latestDream?.created ?? null,
    sessions_since_last_dream: sinceList,
    suggestion_threshold: 5,
    suggestion_shown_at: null,
    last_shown_count: 0
  };
}

// CLI
if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const get = (flag) => {
    const i = args.indexOf(flag);
    return i >= 0 ? args[i + 1] : null;
  };
  const cmd = args[0];
  const ledgerPath = get('--ledger');
  if (!ledgerPath) {
    console.error('usage: ledger.mjs <cmd> --ledger <path>');
    process.exit(2);
  }

  async function loadLedger() {
    try { return JSON.parse(await fs.readFile(ledgerPath, 'utf8')); }
    catch { return emptyLedger(); }
  }
  async function saveLedger(l) {
    const tmp = `${ledgerPath}.tmp`;
    await fs.writeFile(tmp, JSON.stringify(l, null, 2) + '\n');
    await fs.rename(tmp, ledgerPath);
  }

  if (cmd === '--rebuild') {
    const manifest = JSON.parse(await fs.readFile(get('--manifest'), 'utf8'));
    const existing = await loadLedger();
    const rebuilt = rebuildFromManifest(manifest);
    rebuilt.suggestion_threshold = existing.suggestion_threshold ?? 5;
    await saveLedger(rebuilt);
  } else if (cmd === '--bump') {
    const l = await loadLedger();
    await saveLedger(bumpAfterResearch(l, get('--slug')));
  } else if (cmd === '--reset') {
    const l = await loadLedger();
    await saveLedger(resetAfterDream(l, get('--run-id'), new Date().toISOString()));
  } else if (cmd === '--suggest?') {
    const l = await loadLedger();
    if (shouldSuggest(l)) {
      await saveLedger(markSuggested(l, new Date().toISOString()));
      process.stdout.write(JSON.stringify({ should: true, count: l.sessions_since_last_dream.length }) + '\n');
      process.exit(0);
    }
    process.stdout.write(JSON.stringify({ should: false, count: l.sessions_since_last_dream.length }) + '\n');
    process.exit(1);
  } else {
    console.error('usage: ledger.mjs --rebuild|--bump|--reset|--suggest? ... --ledger <path>');
    process.exit(2);
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```
npx vitest run lib/memory/ledger.test.mjs
```

Expected: PASS — 10/10.

- [ ] **Step 5: Commit**

```bash
git add lib/memory/ledger.mjs lib/memory/ledger.test.mjs
git commit -m "feat(memory): ledger — 카운터 상태기계 + rebuild/bump/reset/suggest? CLI"
```

---

## Task 5: memory_reindex.sh — idempotent atomic reindex (RED → GREEN → COMMIT)

**Files:**
- Create: `scripts/memory_reindex.sh`
- Create: `tests/research-engine/memory.test.sh`
- Create: `tests/research-engine/fixtures/memory/manifest-3-sessions/research/{2026-05-01-fixture-a,2026-05-02-fixture-b,2026-05-03-fixture-c}/{README.md,sources.json,intent.json}`

- [ ] **Step 1: 3-sessions fixture 생성**

```bash
mkdir -p tests/research-engine/fixtures/memory/manifest-3-sessions/research/{2026-05-01-fixture-a,2026-05-02-fixture-b,2026-05-03-fixture-c}
mkdir -p tests/research-engine/fixtures/memory/manifest-3-sessions/docs/dreams
```

**fixture-a** (youtube + youtube 캡션 학습):

`research/2026-05-01-fixture-a/README.md`:
```markdown
---
title: "Fixture A"
slug: "2026-05-01-fixture-a"
input_type: "youtube"
created: "2026-05-01T10:00:00+09:00"
---

## 핵심 포인트

- youtube 캡션 처리 패턴
```

`research/2026-05-01-fixture-a/sources.json`:
```json
{
  "input": "https://youtu.be/fixture-a",
  "input_type": "youtube",
  "intent": { "purpose": "youtube 캡션 패턴 학습", "focus": "yt-dlp", "audience_level": "엔지니어" },
  "created": "2026-05-01T10:00:00+09:00",
  "content_sha256": "fixture-hash-a",
  "created_by": [{ "actor_type": "adapter", "id": "youtube-adapter", "model": "claude-opus-4-7", "ts": "2026-05-01T10:00:00+09:00" }],
  "sources": [{ "n": 1, "adapter": "youtube", "type": "youtube-captions", "url": "https://youtu.be/fixture-a", "title": "Fixture A" }]
}
```

`research/2026-05-01-fixture-a/intent.json`:
```json
{ "purpose": "youtube 캡션 패턴 학습", "focus": "yt-dlp", "audience_level": "엔지니어", "intent_mode": "user" }
```

**fixture-b** (arxiv + 에이전트 메모리 논문):

`research/2026-05-02-fixture-b/README.md`:
```markdown
---
title: "Fixture B"
slug: "2026-05-02-fixture-b"
input_type: "arxiv"
created: "2026-05-02T10:00:00+09:00"
---

## 핵심 포인트

- 에이전트 메모리 논문 분석
```

`research/2026-05-02-fixture-b/sources.json`:
```json
{
  "input": "https://arxiv.org/abs/fixture-b",
  "input_type": "arxiv",
  "intent": { "purpose": "에이전트 메모리 논문 정리", "focus": "MemGPT", "audience_level": "엔지니어" },
  "created": "2026-05-02T10:00:00+09:00",
  "content_sha256": "fixture-hash-b",
  "created_by": [{ "actor_type": "adapter", "id": "arxiv-adapter", "model": "claude-opus-4-7", "ts": "2026-05-02T10:00:00+09:00" }],
  "sources": [{ "n": 1, "adapter": "arxiv", "type": "arxiv-paper", "url": "https://arxiv.org/abs/fixture-b", "title": "Fixture B" }]
}
```

`research/2026-05-02-fixture-b/intent.json`:
```json
{ "purpose": "에이전트 메모리 논문 정리", "focus": "MemGPT", "audience_level": "엔지니어", "intent_mode": "user" }
```

**fixture-c** (youtube + 에이전트 메모리 영상):

`research/2026-05-03-fixture-c/README.md`:
```markdown
---
title: "Fixture C"
slug: "2026-05-03-fixture-c"
input_type: "youtube"
created: "2026-05-03T10:00:00+09:00"
---

## 핵심 포인트

- 에이전트 메모리 영상 분석
```

`research/2026-05-03-fixture-c/sources.json`:
```json
{
  "input": "https://youtu.be/fixture-c",
  "input_type": "youtube",
  "intent": { "purpose": "에이전트 메모리 영상 정리", "focus": "memory dreaming", "audience_level": "엔지니어" },
  "created": "2026-05-03T10:00:00+09:00",
  "content_sha256": "fixture-hash-c",
  "created_by": [{ "actor_type": "adapter", "id": "youtube-adapter", "model": "claude-opus-4-7", "ts": "2026-05-03T10:00:00+09:00" }],
  "sources": [{ "n": 1, "adapter": "youtube", "type": "youtube-captions", "url": "https://youtu.be/fixture-c", "title": "Fixture C" }]
}
```

`research/2026-05-03-fixture-c/intent.json`:
```json
{ "purpose": "에이전트 메모리 영상 정리", "focus": "memory dreaming", "audience_level": "엔지니어", "intent_mode": "user" }
```

- [ ] **Step 2: 실패 bats 작성**

`tests/research-engine/memory.test.sh`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  FIXTURE_BASE="${REPO_ROOT}/tests/research-engine/fixtures/memory"
  TMP_HOME="$(mktemp -d)"
  cp -r "${FIXTURE_BASE}/manifest-3-sessions"/. "${TMP_HOME}/"
  export REPO_ROOT TMP_HOME
}

teardown() {
  rm -rf "${TMP_HOME}"
}

@test "memory_reindex: 빈 디렉토리 → 빈 sessions·dreams manifest" {
  EMPTY_DIR="$(mktemp -d)"
  mkdir -p "${EMPTY_DIR}/research" "${EMPTY_DIR}/docs/dreams"
  cd "${EMPTY_DIR}"
  run bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  [ "$status" -eq 0 ]
  [ -f "${EMPTY_DIR}/research/_index/manifest.json" ]
  [ "$(jq '.sessions | length' "${EMPTY_DIR}/research/_index/manifest.json")" = "0" ]
  [ "$(jq '.dreams | length' "${EMPTY_DIR}/research/_index/manifest.json")" = "0" ]
  rm -rf "${EMPTY_DIR}"
}

@test "memory_reindex: 3-sessions fixture → manifest.sessions.length == 3" {
  cd "${TMP_HOME}"
  run bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  [ "$status" -eq 0 ]
  [ "$(jq '.sessions | length' "${TMP_HOME}/research/_index/manifest.json")" = "3" ]
}

@test "memory_reindex: 두 번 연속 실행 결과 byte-identical (idempotent)" {
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  jq 'del(.generated_at) | del(.generator)' "${TMP_HOME}/research/_index/manifest.json" > /tmp/m1.json
  sleep 1
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  jq 'del(.generated_at) | del(.generator)' "${TMP_HOME}/research/_index/manifest.json" > /tmp/m2.json
  run diff /tmp/m1.json /tmp/m2.json
  [ "$status" -eq 0 ]
}

@test "memory_reindex: 기존 세션 파일 mtime 불변" {
  cd "${TMP_HOME}"
  before=$(stat -c %Y "${TMP_HOME}/research/2026-05-01-fixture-a/sources.json")
  sleep 1
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  after=$(stat -c %Y "${TMP_HOME}/research/2026-05-01-fixture-a/sources.json")
  [ "$before" = "$after" ]
}

@test "memory_reindex: ledger 동시 생성" {
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  [ -f "${TMP_HOME}/research/_index/dream-ledger.json" ]
  [ "$(jq '.version' "${TMP_HOME}/research/_index/dream-ledger.json")" = "1" ]
  [ "$(jq '.sessions_since_last_dream | length' "${TMP_HOME}/research/_index/dream-ledger.json")" = "3" ]
}
```

- [ ] **Step 3: 테스트 실패 확인**

```
bats tests/research-engine/memory.test.sh
```

Expected: FAIL — `scripts/memory_reindex.sh` 부재.

- [ ] **Step 4: 최소 구현**

`scripts/memory_reindex.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CWD="$(pwd)"

INDEX_DIR="${CWD}/research/_index"
RESEARCH_DIR="${CWD}/research"
DREAMS_DIR="${CWD}/docs/dreams"

mkdir -p "${INDEX_DIR}"

TMP_MANIFEST="${INDEX_DIR}/manifest.json.tmp.$$"
node "${REPO_ROOT}/lib/memory/manifest_schema.mjs" --build \
  --research-dir "${RESEARCH_DIR}" \
  --dreams-dir "${DREAMS_DIR}" \
  > "${TMP_MANIFEST}"
mv "${TMP_MANIFEST}" "${INDEX_DIR}/manifest.json"

node "${REPO_ROOT}/lib/memory/ledger.mjs" --rebuild \
  --manifest "${INDEX_DIR}/manifest.json" \
  --ledger "${INDEX_DIR}/dream-ledger.json"

n_sessions=$(jq '.sessions | length' "${INDEX_DIR}/manifest.json")
n_dreams=$(jq '.dreams | length' "${INDEX_DIR}/manifest.json")
echo "memory_reindex: ${n_sessions} sessions, ${n_dreams} dreams"
```

- [ ] **Step 5: 실행 권한**

```bash
chmod +x scripts/memory_reindex.sh
```

- [ ] **Step 6: 테스트 통과 확인**

```
bats tests/research-engine/memory.test.sh
```

Expected: PASS — 5/5.

- [ ] **Step 7: Commit**

```bash
git add scripts/memory_reindex.sh tests/research-engine/memory.test.sh \
       tests/research-engine/fixtures/memory/manifest-3-sessions
git commit -m "feat(memory): memory_reindex.sh — idempotent atomic reindex + bats"
```

---

## Task 6: memory_query.sh — fail-soft top-K (RED → GREEN → COMMIT)

**Files:**
- Create: `scripts/memory_query.sh`
- Modify: `tests/research-engine/memory.test.sh` — query 테스트 3건 append

- [ ] **Step 1: bats RED 추가**

`tests/research-engine/memory.test.sh` 끝에 append:

```bash
@test "memory_query: manifest 부재 시 빈 결과 + exit 0 (fail-soft)" {
  EMPTY_DIR="$(mktemp -d)"
  mkdir -p "${EMPTY_DIR}/research"
  cd "${EMPTY_DIR}"
  TARGET_JSON='{"input_type":"youtube","topics":["agent memory"],"intent":{"purpose":"메모리 패턴"}}'
  run bash "${REPO_ROOT}/scripts/memory_query.sh" --target-json "${TARGET_JSON}"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '.similar_sessions | length')" = "0" ]
  [ "$(echo "$output" | jq '.dream_insights | length')" = "0" ]
  rm -rf "${EMPTY_DIR}"
}

@test "memory_query: 3-sessions fixture → youtube 유사 검색 시 1~2개 반환" {
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  TARGET_JSON='{"input_type":"youtube","topics":[],"intent":{"purpose":"에이전트 메모리 영상 정리"}}'
  run bash "${REPO_ROOT}/scripts/memory_query.sh" --target-json "${TARGET_JSON}" --top-k 5
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq '.similar_sessions | length')
  [ "$count" -ge 1 ]
  [ "$count" -le 2 ]
}

@test "memory_query: --self-slug 자기 제외" {
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  TARGET_JSON='{"input_type":"youtube","topics":[],"intent":{"purpose":"에이전트 메모리 영상 정리"}}'
  run bash "${REPO_ROOT}/scripts/memory_query.sh" --target-json "${TARGET_JSON}" --top-k 5 --self-slug 2026-05-03-fixture-c
  [ "$status" -eq 0 ]
  ! echo "$output" | jq -r '.similar_sessions[].slug' | grep -q "2026-05-03-fixture-c"
}
```

```
bats tests/research-engine/memory.test.sh -f memory_query
```

Expected: FAIL.

- [ ] **Step 2: 최소 구현**

`scripts/memory_query.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail   # -e 빼고 fail-soft

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CWD="$(pwd)"

MANIFEST="${CWD}/research/_index/manifest.json"
TOP_K=5
TARGET_JSON=""
SELF_SLUG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --target-json) TARGET_JSON="$2"; shift 2 ;;
    --top-k) TOP_K="$2"; shift 2 ;;
    --self-slug) SELF_SLUG="$2"; shift 2 ;;
    *) shift ;;
  esac
done

empty='{"similar_sessions":[],"dream_insights":[]}'

if [ ! -f "${MANIFEST}" ]; then
  echo "memory_query: manifest missing, run memory_reindex.sh to generate" >&2
  echo "${empty}"
  exit 0
fi

if [ -z "${TARGET_JSON}" ]; then
  echo "memory_query: --target-json required" >&2
  echo "${empty}"
  exit 0
fi

# Node 호출: similarity.topK + active dream filter
TARGET_JSON="${TARGET_JSON}" \
SELF_SLUG="${SELF_SLUG}" \
MANIFEST_PATH="${MANIFEST}" \
TOP_K="${TOP_K}" \
REPO_ROOT_PATH="${REPO_ROOT}" \
node --input-type=module -e '
import { topK } from process.env.REPO_ROOT_PATH + "/lib/memory/similarity.mjs";
import { tokenize } from process.env.REPO_ROOT_PATH + "/lib/memory/tokenize.mjs";
import fs from "node:fs/promises";

const manifest = JSON.parse(await fs.readFile(process.env.MANIFEST_PATH, "utf8"));
const target = JSON.parse(process.env.TARGET_JSON);
target.slug = process.env.SELF_SLUG || null;
target.intent = target.intent ?? {};
const purposeText = (target.intent.purpose ?? "") + " " + (target.intent.focus ?? "");
target.intent.purpose_tokens = tokenize(purposeText);

const similar = topK(target, manifest.sessions ?? [], parseInt(process.env.TOP_K)).map(s => ({
  slug: s.slug,
  title: s.title,
  input_type: s.input_type,
  input: s.input,
  topics: s.topics,
  notion_url: s.notion_url,
  path: s.path,
  score: s._score
}));

const active_dreams = (manifest.dreams ?? []).filter(d => d.status === "active").map(d => ({
  run_id: d.run_id,
  path: d.path,
  insight_files: d.insight_files,
  inputs: d.inputs
}));

process.stdout.write(JSON.stringify({ similar_sessions: similar, dream_insights: active_dreams }) + "\n");
' 2>/dev/null || { echo "${empty}"; exit 0; }
```

**Note on dynamic imports:** Node ESM은 `import process.env.X + "..."` 형태의 동적 import를 직접 못 한다. 위 코드는 의도를 보여주는 의사 코드 — 실제로는 `await import()`로 바꿔야 한다. 진짜 구현:

```javascript
const { topK } = await import(process.env.REPO_ROOT_PATH + "/lib/memory/similarity.mjs");
const { tokenize } = await import(process.env.REPO_ROOT_PATH + "/lib/memory/tokenize.mjs");
```

이 패턴으로 shell 인라인 작성 시 다음과 같이 한 줄 -e 인자로 전달:

```bash
node --input-type=module -e "$(cat <<'EOF'
const { topK } = await import(process.env.REPO_ROOT_PATH + '/lib/memory/similarity.mjs');
const { tokenize } = await import(process.env.REPO_ROOT_PATH + '/lib/memory/tokenize.mjs');
const fs = await import('node:fs/promises');
const manifest = JSON.parse(await fs.readFile(process.env.MANIFEST_PATH, 'utf8'));
const target = JSON.parse(process.env.TARGET_JSON);
target.slug = process.env.SELF_SLUG || null;
target.intent = target.intent ?? {};
const purposeText = (target.intent.purpose ?? '') + ' ' + (target.intent.focus ?? '');
target.intent.purpose_tokens = tokenize(purposeText);
const similar = topK(target, manifest.sessions ?? [], parseInt(process.env.TOP_K)).map(s => ({
  slug: s.slug, title: s.title, input_type: s.input_type, input: s.input,
  topics: s.topics, notion_url: s.notion_url, path: s.path, score: s._score
}));
const active_dreams = (manifest.dreams ?? []).filter(d => d.status === 'active').map(d => ({
  run_id: d.run_id, path: d.path, insight_files: d.insight_files, inputs: d.inputs
}));
process.stdout.write(JSON.stringify({ similar_sessions: similar, dream_insights: active_dreams }) + '\n');
EOF
)"
```

또는 `lib/memory/query_cli.mjs`라는 작은 wrapper를 만들어 shell에서 `node lib/memory/query_cli.mjs --target-json ...` 호출. **이쪽이 더 깔끔.** 다음 step에서 이 wrapper로 갱신.

- [ ] **Step 3: lib/memory/query_cli.mjs wrapper 생성 (shell 단순화)**

`lib/memory/query_cli.mjs`:

```javascript
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { topK } from './similarity.mjs';
import { tokenize } from './tokenize.mjs';

const args = process.argv.slice(2);
const get = (flag) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : null;
};

const manifestPath = get('--manifest');
const targetJson = get('--target-json');
const selfSlug = get('--self-slug') ?? null;
const k = parseInt(get('--top-k') ?? '5', 10);

const empty = { similar_sessions: [], dream_insights: [] };

try {
  if (!manifestPath || !targetJson) {
    process.stdout.write(JSON.stringify(empty) + '\n');
    process.exit(0);
  }
  const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  const target = JSON.parse(targetJson);
  target.slug = selfSlug;
  target.intent = target.intent ?? {};
  const purposeText = (target.intent.purpose ?? '') + ' ' + (target.intent.focus ?? '');
  target.intent.purpose_tokens = tokenize(purposeText);

  const similar = topK(target, manifest.sessions ?? [], k).map(s => ({
    slug: s.slug,
    title: s.title,
    input_type: s.input_type,
    input: s.input,
    topics: s.topics,
    notion_url: s.notion_url,
    path: s.path,
    score: s._score
  }));

  const active_dreams = (manifest.dreams ?? [])
    .filter(d => d.status === 'active')
    .map(d => ({ run_id: d.run_id, path: d.path, insight_files: d.insight_files, inputs: d.inputs }));

  process.stdout.write(JSON.stringify({ similar_sessions: similar, dream_insights: active_dreams }) + '\n');
} catch (err) {
  process.stderr.write(`query_cli: ${err.message}\n`);
  process.stdout.write(JSON.stringify(empty) + '\n');
  process.exit(0);
}
```

- [ ] **Step 4: scripts/memory_query.sh를 wrapper 호출로 단순화**

`scripts/memory_query.sh` (재작성):

```bash
#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CWD="$(pwd)"

MANIFEST="${CWD}/research/_index/manifest.json"
TOP_K=5
TARGET_JSON=""
SELF_SLUG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --target-json) TARGET_JSON="$2"; shift 2 ;;
    --top-k) TOP_K="$2"; shift 2 ;;
    --self-slug) SELF_SLUG="$2"; shift 2 ;;
    *) shift ;;
  esac
done

empty='{"similar_sessions":[],"dream_insights":[]}'

if [ ! -f "${MANIFEST}" ]; then
  echo "memory_query: manifest missing, run memory_reindex.sh to generate" >&2
  echo "${empty}"
  exit 0
fi

if [ -z "${TARGET_JSON}" ]; then
  echo "memory_query: --target-json required" >&2
  echo "${empty}"
  exit 0
fi

# delegate to Node CLI
if [ -n "${SELF_SLUG}" ]; then
  node "${REPO_ROOT}/lib/memory/query_cli.mjs" \
    --manifest "${MANIFEST}" \
    --target-json "${TARGET_JSON}" \
    --top-k "${TOP_K}" \
    --self-slug "${SELF_SLUG}"
else
  node "${REPO_ROOT}/lib/memory/query_cli.mjs" \
    --manifest "${MANIFEST}" \
    --target-json "${TARGET_JSON}" \
    --top-k "${TOP_K}"
fi
```

- [ ] **Step 5: 실행 권한**

```bash
chmod +x scripts/memory_query.sh
```

- [ ] **Step 6: 테스트 통과 확인**

```
bats tests/research-engine/memory.test.sh
```

Expected: PASS — 8/8 (5 reindex + 3 query).

- [ ] **Step 7: Commit**

```bash
git add scripts/memory_query.sh lib/memory/query_cli.mjs tests/research-engine/memory.test.sh
git commit -m "feat(memory): memory_query.sh + query_cli.mjs — fail-soft top-K + bats"
```

---

## Task 7: `/research` Stage 2 prior query hook (RED → GREEN → COMMIT)

**Files:**
- Create: `tests/research-engine/research-with-memory.test.sh`
- Modify: `commands/research.md`

- [ ] **Step 1: RED bats — Stage 2 hook 효과 검증**

`tests/research-engine/research-with-memory.test.sh`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  TMP_HOME="$(mktemp -d)"
  cp -r "${REPO_ROOT}/tests/research-engine/fixtures/memory/manifest-3-sessions"/. "${TMP_HOME}/"
  mkdir -p "${TMP_HOME}/research/2026-06-01-new-target/cache"
  export REPO_ROOT TMP_HOME
}

teardown() {
  rm -rf "${TMP_HOME}"
}

@test "Stage 2 hook: memory_query 결과가 cache/memory.json에 쓰인다 + self-exclusion" {
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"

  TARGET_JSON='{"input_type":"youtube","topics":[],"intent":{"purpose":"새 메모리 영상"},"slug":"2026-06-01-new-target"}'
  bash "${REPO_ROOT}/scripts/memory_query.sh" \
    --target-json "${TARGET_JSON}" \
    --top-k 5 \
    --self-slug 2026-06-01-new-target \
    > "${TMP_HOME}/research/2026-06-01-new-target/cache/memory.json"

  [ -f "${TMP_HOME}/research/2026-06-01-new-target/cache/memory.json" ]
  [ "$(jq '.similar_sessions | length' "${TMP_HOME}/research/2026-06-01-new-target/cache/memory.json")" -ge 1 ]
  ! jq -r '.similar_sessions[].slug' "${TMP_HOME}/research/2026-06-01-new-target/cache/memory.json" | grep -q "2026-06-01-new-target"
}
```

```
bats tests/research-engine/research-with-memory.test.sh
```

Expected: PASS — 1/1 (스크립트 합성으로 검증, 명세 자체는 markdown).

- [ ] **Step 2: commands/research.md Stage 2 끝부분에 hook 추가**

`commands/research.md` Stage 2 섹션 끝(`Write the preview to ...` 줄 다음)에 추가:

```markdown
### Stage 2.5 — Memory Query (prior_knowledge 자동 조회)

After preview JSON is written, query memory for similar past sessions before moving to Stage 3:

```bash
# Build a target descriptor from preview-level info
TARGET_JSON=$(jq -nc \
  --arg t "<input_type>" \
  --arg p "<intent.purpose 후보 (preview title/description에서 추출, 또는 빈 문자열)>" \
  --arg sl "<slug 잠정>" \
  --argjson topics '[]' \
  '{input_type: $t, topics: $topics, intent: {purpose: $p}, slug: $sl}')

bash "${PLUGIN_ROOT}/scripts/memory_query.sh" \
  --target-json "${TARGET_JSON}" \
  --top-k 5 \
  --self-slug "<slug>" \
  > "<report_dir>/cache/memory.json"
```

The query runs BEFORE Stage 3 Intent Q&A. At this point you only have preview-level info — that's enough for similarity matching. The result `cache/memory.json` is consumed in Stage 4 dispatch as `prior_knowledge`.

If `cache/memory.json` is `{"similar_sessions":[],"dream_insights":[]}` (no priors), proceed normally — memory is optional and silently absent on first runs.
```

- [ ] **Step 3: 통과 확인**

```
bats tests/research-engine/research-with-memory.test.sh
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add commands/research.md tests/research-engine/research-with-memory.test.sh
git commit -m "feat(research): Stage 2.5 memory_query hook + research-with-memory bats"
```

---

## Task 8: `/research` Stage 5.2 — sources.json에 content_sha256 + created_by

**Files:**
- Modify: `commands/research.md`
- Modify: `tests/research-engine/research-with-memory.test.sh` — 검증 케이스 append

- [ ] **Step 1: RED 테스트 append**

`tests/research-engine/research-with-memory.test.sh` 끝에 append:

```bash
@test "Stage 5.2: 신규 세션 sources.json에 content_sha256 + created_by가 기록된다" {
  cd "${TMP_HOME}"
  NEW_SLUG="2026-06-01-new-target"
  mkdir -p "${TMP_HOME}/research/${NEW_SLUG}"
  cat > "${TMP_HOME}/research/${NEW_SLUG}/README.md" <<'EOF'
---
title: "New target"
slug: "2026-06-01-new-target"
input_type: "youtube"
created: "2026-06-01T10:00:00+09:00"
---

# new target body
EOF

  hash=$(sha256sum "${TMP_HOME}/research/${NEW_SLUG}/README.md" | awk '{print $1}')
  jq -nc \
    --arg input "https://youtu.be/new" \
    --arg type "youtube" \
    --arg created "2026-06-01T10:00:00+09:00" \
    --arg hash "$hash" \
    '{
      input: $input,
      input_type: $type,
      created: $created,
      content_sha256: $hash,
      created_by: [
        {actor_type: "adapter", id: "youtube-adapter", model: "claude-opus-4-7", ts: $created}
      ],
      sources: []
    }' > "${TMP_HOME}/research/${NEW_SLUG}/sources.json"

  [ "$(jq -r '.content_sha256' "${TMP_HOME}/research/${NEW_SLUG}/sources.json")" = "$hash" ]
  [ "$(jq '.created_by | length' "${TMP_HOME}/research/${NEW_SLUG}/sources.json")" -ge 1 ]
}
```

```
bats tests/research-engine/research-with-memory.test.sh -f "Stage 5.2"
```

Expected: PASS.

- [ ] **Step 2: commands/research.md Stage 5 step 2 명세 갱신**

`commands/research.md` Stage 5 step 2 (Write sources.json) 직후에 추가:

```markdown
**Required NEW fields** (research-engine v0.13+):

- `content_sha256`: After writing `<report_dir>/README.md` in step 3, compute its sha256 with `sha256sum <report_dir>/README.md | awk '{print $1}'` and patch it into `sources.json`. Order: write README.md → hash it → patch sources.json. README.md is the *content fingerprint authority*.
- `created_by`: Array of actors. For each adapter that contributed (Stage 4 dispatch), add `{actor_type: "adapter", id: "<adapter-name>", model: "<model-id-or-unknown>", ts: "<adapter-completion-ISO8601>"}`. Order: list adapters in the order they returned.

After step 7 (Notion push) prepends the `> 📒 Notion:` line to README.md, **recompute the sha256 and patch `sources.json.content_sha256`** so it always matches README.md byte-for-byte.
```

- [ ] **Step 3: 통과 확인**

```
bats tests/research-engine/research-with-memory.test.sh
```

Expected: PASS — 2/2.

- [ ] **Step 4: Commit**

```bash
git add commands/research.md tests/research-engine/research-with-memory.test.sh
git commit -m "feat(research): Stage 5.2 content_sha256 + created_by 기록 명세"
```

---

## Task 9: `/research` Stage 4 — prior_knowledge 주입 명세

**Files:**
- Modify: `commands/research.md`

- [ ] **Step 1: Stage 4 dispatch prompt template 갱신**

`commands/research.md` Stage 4 prompt template (`You are dispatched as ...`)을 다음과 같이 변경:

```
You are dispatched as the <adapter-name> subagent for research session <slug>.

Inputs:
  <JSON of {url|targets|libraries|thread_urls, intent, cache_dir, slug, fresh, prior_knowledge}>

prior_knowledge (when non-empty) contains the contents of <report_dir>/cache/memory.json — similar past sessions and active dream insights from the research-engine memory layer. Treat it as HINTS only, not verified facts. If you reuse a finding from prior_knowledge, you MUST cite the prior session/dream via its slug or run_id in your `findings[].sources[]` or in a `failures[]` note. Do not blindly copy prior findings — fresh sources still take priority. If prior_knowledge is empty `{similar_sessions:[],dream_insights:[]}`, proceed normally.

Return a single fenced JSON block per lib/adapter_contract.md. Do not include anything after the JSON block.
```

또한 dispatcher 단계 (Stage 4 시작)에서:

```
dispatcher reads <report_dir>/cache/memory.json once and includes the same JSON as the `prior_knowledge` field in every adapter's input.
```

- [ ] **Step 2: Commit (markdown only)**

```
bats tests/research-engine/research-with-memory.test.sh
```

Expected: PASS — 회귀 없음.

```bash
git add commands/research.md
git commit -m "feat(research): Stage 4 dispatch에 prior_knowledge guidance + citation 요건"
```

---

## Task 10: `/research` Stage 5.8 — ledger update + 제안 (RED → GREEN → COMMIT)

**Files:**
- Modify: `commands/research.md`
- Modify: `tests/research-engine/research-with-memory.test.sh`

- [ ] **Step 1: RED 테스트 append**

`tests/research-engine/research-with-memory.test.sh` 끝에 append:

```bash
@test "Stage 5.8: 신규 세션 추가 후 reindex → ledger 카운터 증가" {
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  before=$(jq '.sessions_since_last_dream | length' "${TMP_HOME}/research/_index/dream-ledger.json")

  NEW_SLUG="2026-06-01-new-target"
  mkdir -p "${TMP_HOME}/research/${NEW_SLUG}"
  cat > "${TMP_HOME}/research/${NEW_SLUG}/README.md" <<'EOF'
---
title: "New"
input_type: "youtube"
created: "2026-06-01T10:00:00+09:00"
---
body
EOF
  echo '{"input_type":"youtube","input":"x","created":"2026-06-01","content_sha256":"abc","created_by":[],"sources":[],"intent":{"purpose":"new","focus":"","audience_level":""}}' \
    > "${TMP_HOME}/research/${NEW_SLUG}/sources.json"

  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  after=$(jq '.sessions_since_last_dream | length' "${TMP_HOME}/research/_index/dream-ledger.json")
  [ "$after" -gt "$before" ]
}

@test "Stage 5.8: 5회 누적 시 ledger --suggest? exit 0 + should=true" {
  cd "${TMP_HOME}"
  # 3개 fixture + 2개 추가 → 5
  for i in 4 5; do
    NEW_SLUG="2026-05-0${i}-extra-fixture-${i}"
    mkdir -p "${TMP_HOME}/research/${NEW_SLUG}"
    cat > "${TMP_HOME}/research/${NEW_SLUG}/README.md" <<EOF
---
title: "Extra ${i}"
input_type: "youtube"
created: "2026-05-0${i}T10:00:00+09:00"
---
body
EOF
    echo "{\"input_type\":\"youtube\",\"input\":\"x${i}\",\"created\":\"2026-05-0${i}\",\"content_sha256\":\"abc${i}\",\"created_by\":[],\"sources\":[],\"intent\":{\"purpose\":\"e${i}\",\"focus\":\"\",\"audience_level\":\"\"}}" \
      > "${TMP_HOME}/research/${NEW_SLUG}/sources.json"
  done
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"

  count=$(jq '.sessions_since_last_dream | length' "${TMP_HOME}/research/_index/dream-ledger.json")
  [ "$count" -eq 5 ]

  run node "${REPO_ROOT}/lib/memory/ledger.mjs" --suggest? --ledger "${TMP_HOME}/research/_index/dream-ledger.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.should == true'
}
```

```
bats tests/research-engine/research-with-memory.test.sh -f "Stage 5.8"
```

Expected: PASS — 2/2.

- [ ] **Step 2: commands/research.md Stage 5 step 8 직전에 추가**

`commands/research.md` Stage 5 step 8 (Final message) 직전:

```markdown
**Step 7.5 — Update dream-ledger + suggestion check**

After step 7 (Notion push), call reindex once so the new session is reflected:

```bash
bash "${PLUGIN_ROOT}/scripts/memory_reindex.sh"
```

This rebuilds `research/_index/manifest.json` and refreshes `dream-ledger.json` (`sessions_since_last_dream` is recomputed from manifest vs `last_dream_at`).

Then check whether to suggest `/dream`:

```bash
node "${PLUGIN_ROOT}/lib/memory/ledger.mjs" --suggest? \
  --ledger "research/_index/dream-ledger.json"
# exit 0 + {"should":true,"count":N}  → 제안 줄을 step 8 final message에 포함
# exit 1 + {"should":false,...}        → 제안 생략
```

If suggest = true, the `--suggest?` CLI also writes `suggestion_shown_at` back to the ledger automatically (so the same threshold isn't nagged repeatedly until the next threshold is crossed). Include exactly this line in step 8's final message:

> 💡 dream-ledger: 마지막 dream 이후 {N}개 세션이 누적되었습니다. `/dream` 으로 패턴 인사이트를 추출할 수 있어요.
```

- [ ] **Step 3: 통과 확인**

```
bats tests/research-engine/research-with-memory.test.sh
```

Expected: PASS — 4/4.

- [ ] **Step 4: Commit**

```bash
git add commands/research.md tests/research-engine/research-with-memory.test.sh
git commit -m "feat(research): Stage 5.8 reindex + ledger --suggest? hook + 5회 누적 제안"
```

---

## Task 11: agents/dream-extractor.md persona

**Files:**
- Create: `agents/dream-extractor.md`

- [ ] **Step 1: persona 작성**

`agents/dream-extractor.md`:

```markdown
---
name: dream-extractor
description: research-engine /dream 슬래시가 호출하는 dream-extractor 에이전트. N개의 과거 research 세션을 입력으로 받아 반복 패턴·어댑터 실패 모드·자주 묻는 의도 클러스터·prior art 군집을 추출해 JSON으로 반환한다.
tools: [Read, Glob, Grep, Bash]
---

# dream-extractor

You are dispatched as the `dream-extractor` subagent inside the research-engine `/dream` slash. Your job: read N past `research/<slug>/` sessions and emit cross-session insights — patterns the user (and downstream `/research` calls) can act on.

## Inputs

The dispatcher passes a single JSON object:

```json
{
  "run_id": "drm_<YYYY-MM-DD-HHMM>-<topic-slug>",
  "session_paths": ["research/2026-05-01-...", "research/2026-05-02-..."],
  "manifest_excerpt": { "sessions": [...] },
  "intent_distribution": { "by_focus": {...}, "by_audience": {...} },
  "bench_excerpt": null
}
```

## Process

1. For each `session_path`: read `README.md`, `sources.json`, `intent.json`, and look for `failures[]` patterns in sources.json.
2. Identify these categories (skip a category if you find <2 instances of evidence):
   - **adapter_failure_modes**: which adapters fail in which contexts? (e.g., context7 quota exhaustion, blog 404, github 404 for assumed-public repos)
   - **recurring_intents**: cluster `intent.purpose` across sessions. Each semantic cluster → 1 insight bullet.
   - **prior_art_clusters**: papers/repos cited in ≥2 sessions — likely *foundational* to the user's interest area.
   - **topic_coverage_gaps**: topics the user repeatedly hits but adapters returned shallow/no results on.
3. If `bench_excerpt` provided, weave bench pass-rate data into adapter_failure_modes.

## Output

Return a SINGLE fenced JSON block. No prose before or after.

```json
{
  "run_id": "...",
  "input_count": N,
  "patterns": {
    "adapter_failure_modes": [
      { "title": "...", "evidence_slugs": ["s1","s2"], "body": "1-3 sentences", "action": "one actionable recommendation" }
    ],
    "recurring_intents": [
      { "cluster_name": "...", "evidence_slugs": [...], "body": "...", "action": "..." }
    ],
    "prior_art_clusters": [
      { "name": "...", "items": ["MemGPT (2310.08560)", "..."], "citation_count": N, "evidence_slugs": [...] }
    ],
    "topic_coverage_gaps": [
      { "topic": "...", "evidence_slugs": [...], "body": "...", "action": "..." }
    ]
  },
  "failures": []
}
```

Each `evidence_slugs` must list ≥2 distinct slugs from `session_paths`. Each `body` is 1–3 sentences. Each `action` is one recommendation for the research-engine maintainer. If a category has <2 evidence items, OMIT that array entirely — better to return 2 strong patterns than 5 weak ones.
```

- [ ] **Step 2: Commit**

```bash
git add agents/dream-extractor.md
git commit -m "feat(dream): dream-extractor agent persona"
```

---

## Task 12: scripts/dream_run.sh — D1·D2·D4~D7 shell wrapper (RED → GREEN → COMMIT)

**Files:**
- Create: `scripts/dream_run.sh`
- Create: `tests/research-engine/dream.test.sh`
- Create: `tests/research-engine/fixtures/dream-input-sessions/research/{...}` — 3 세션 fixture

- [ ] **Step 1: dream-input-sessions fixture 생성**

```bash
mkdir -p tests/research-engine/fixtures/dream-input-sessions/research/{2026-05-10-dream-input-a,2026-05-11-dream-input-b,2026-05-12-dream-input-c}
mkdir -p tests/research-engine/fixtures/dream-input-sessions/docs/dreams
```

각 세션마다 README.md + sources.json + intent.json — Task 5의 fixture 형식과 동일하게 (input_type=arxiv, 모두 topic "agent memory" 공유).

예: `tests/research-engine/fixtures/dream-input-sessions/research/2026-05-10-dream-input-a/sources.json`:

```json
{
  "input": "https://arxiv.org/abs/2310.08560",
  "input_type": "arxiv",
  "intent": { "purpose": "에이전트 메모리 prior art", "focus": "MemGPT", "audience_level": "엔지니어" },
  "created": "2026-05-10T10:00:00+09:00",
  "content_sha256": "dream-input-hash-a",
  "created_by": [{ "actor_type": "adapter", "id": "arxiv-adapter", "model": "claude-opus-4-7", "ts": "2026-05-10T10:00:00+09:00" }],
  "sources": [{ "n": 1, "adapter": "arxiv", "type": "arxiv-paper", "url": "https://arxiv.org/abs/2310.08560", "title": "MemGPT" }]
}
```

(b, c도 동일 형식으로 input과 dates만 다르게.)

- [ ] **Step 2: RED bats — dream_run.sh 4가지 시나리오**

`tests/research-engine/dream.test.sh`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  TMP_HOME="$(mktemp -d)"
  cp -r "${REPO_ROOT}/tests/research-engine/fixtures/dream-input-sessions"/. "${TMP_HOME}/"
  export REPO_ROOT TMP_HOME
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
}

teardown() {
  rm -rf "${TMP_HOME}"
}

@test "dream_run: 입력 세션 < 2 → not enough sessions 에러" {
  SINGLE=$(jq -r '.sessions[0].slug' "${TMP_HOME}/research/_index/manifest.json")
  run bash "${REPO_ROOT}/scripts/dream_run.sh" --resolve-only --slugs "${SINGLE}"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "not enough sessions"
}

@test "dream_run: --slugs=a,b,c → 정확히 3개 resolved" {
  ALL_SLUGS=$(jq -r '.sessions | map(.slug) | join(",")' "${TMP_HOME}/research/_index/manifest.json")
  run bash "${REPO_ROOT}/scripts/dream_run.sh" --resolve-only --slugs "${ALL_SLUGS}"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.resolved | length == 3'
}

@test "dream_run: --mint-only → 디렉토리 + meta.json 생성" {
  ALL_SLUGS=$(jq -r '.sessions | map(.slug) | join(",")' "${TMP_HOME}/research/_index/manifest.json")
  run bash "${REPO_ROOT}/scripts/dream_run.sh" --mint-only --slugs "${ALL_SLUGS}"
  [ "$status" -eq 0 ]
  RUN_ID=$(echo "$output" | jq -r '.run_id')
  [ -d "${TMP_HOME}/docs/dreams/${RUN_ID}" ]
  [ -d "${TMP_HOME}/docs/dreams/${RUN_ID}/insights" ]
  [ -f "${TMP_HOME}/docs/dreams/${RUN_ID}/meta.json" ]
}

@test "dream_run: --finalize → insights/ + README.md + sources.json + ledger 리셋" {
  ALL_SLUGS=$(jq -r '.sessions | map(.slug) | join(",")' "${TMP_HOME}/research/_index/manifest.json")
  MINT=$(bash "${REPO_ROOT}/scripts/dream_run.sh" --mint-only --slugs "${ALL_SLUGS}")
  RUN_ID=$(echo "${MINT}" | jq -r '.run_id')

  cat > /tmp/dream-output.json <<EOF
{
  "run_id": "${RUN_ID}",
  "input_count": 3,
  "patterns": {
    "recurring_intents": [
      { "cluster_name": "agent memory", "evidence_slugs": ["2026-05-10-dream-input-a","2026-05-11-dream-input-b"], "body": "사용자가 agent memory 주제를 반복 검색함", "action": "research-engine memory query에 agent memory 토픽 boost 권장" }
    ]
  },
  "failures": []
}
EOF

  run bash "${REPO_ROOT}/scripts/dream_run.sh" --finalize --run-id "${RUN_ID}" --agent-output /tmp/dream-output.json
  [ "$status" -eq 0 ]
  [ -f "${TMP_HOME}/docs/dreams/${RUN_ID}/README.md" ]
  [ -f "${TMP_HOME}/docs/dreams/${RUN_ID}/sources.json" ]
  [ -f "${TMP_HOME}/docs/dreams/${RUN_ID}/insights/pattern-recurring-intents.md" ]
  [ "$(jq -r '.last_dream_run_id' "${TMP_HOME}/research/_index/dream-ledger.json")" = "${RUN_ID}" ]
  [ "$(jq '.sessions_since_last_dream | length' "${TMP_HOME}/research/_index/dream-ledger.json")" = "0" ]
}
```

```
bats tests/research-engine/dream.test.sh
```

Expected: FAIL — `scripts/dream_run.sh` 부재.

- [ ] **Step 3: 최소 구현**

`scripts/dream_run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CWD="$(pwd)"

MODE=""
SLUGS=""
SINCE=""
RUN_ID=""
AGENT_OUTPUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --resolve-only) MODE="resolve"; shift ;;
    --mint-only) MODE="mint"; shift ;;
    --finalize) MODE="finalize"; shift ;;
    --slugs) SLUGS="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --agent-output) AGENT_OUTPUT="$2"; shift 2 ;;
    *) echo "dream_run: unknown arg $1" >&2; exit 2 ;;
  esac
done

MANIFEST="${CWD}/research/_index/manifest.json"
LEDGER="${CWD}/research/_index/dream-ledger.json"

[ -f "${MANIFEST}" ] || { echo "dream_run: manifest not found, run memory_reindex.sh first" >&2; exit 3; }

resolve_inputs() {
  if [ -n "${SLUGS}" ]; then
    echo "${SLUGS}" | tr ',' '\n' | jq -R . | jq -s '{resolved: .}'
  elif [ -n "${SINCE}" ]; then
    days="${SINCE%d}"
    cutoff=$(date -u -d "${days} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ)
    jq --arg cutoff "${cutoff}" '{resolved: [.sessions[] | select(.created >= $cutoff) | .slug]}' "${MANIFEST}"
  else
    jq '{resolved: .sessions_since_last_dream}' "${LEDGER}"
  fi
}

case "${MODE}" in
  resolve)
    R=$(resolve_inputs)
    n=$(echo "${R}" | jq '.resolved | length')
    if [ "${n}" -lt 2 ]; then echo "dream_run: not enough sessions (${n} < 2)" >&2; exit 4; fi
    echo "${R}"
    ;;
  mint)
    R=$(resolve_inputs)
    n=$(echo "${R}" | jq '.resolved | length')
    if [ "${n}" -lt 2 ]; then echo "dream_run: not enough sessions (${n} < 2)" >&2; exit 4; fi
    TS=$(date +%Y-%m-%d-%H%M)
    first_slug=$(echo "${R}" | jq -r '.resolved[0]')
    topic_slug=$(jq -r --arg s "${first_slug}" '.sessions[] | select(.slug == $s) | .topics[0] // "mixed"' "${MANIFEST}" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | head -c 40)
    [ -z "${topic_slug}" ] && topic_slug="mixed"
    RUN_ID="drm_${TS}-${topic_slug}"
    mkdir -p "${CWD}/docs/dreams/${RUN_ID}/insights"
    jq -nc \
      --arg run_id "${RUN_ID}" \
      --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson resolved "$(echo "${R}" | jq '.resolved')" \
      '{run_id: $run_id, generated_at: $now, prompt_version: "v1", model: "claude-opus-4-7", input_count: ($resolved | length), inputs: $resolved}' \
      > "${CWD}/docs/dreams/${RUN_ID}/meta.json"
    jq -nc --arg run_id "${RUN_ID}" --argjson resolved "$(echo "${R}" | jq '.resolved')" '{run_id: $run_id, resolved: $resolved}'
    ;;
  finalize)
    [ -n "${RUN_ID}" ] || { echo "dream_run --finalize: --run-id required" >&2; exit 2; }
    [ -f "${AGENT_OUTPUT}" ] || { echo "dream_run --finalize: --agent-output file missing" >&2; exit 2; }
    DREAM_DIR="${CWD}/docs/dreams/${RUN_ID}"
    [ -d "${DREAM_DIR}" ] || { echo "dream_run: ${DREAM_DIR} not found (run --mint-only first)" >&2; exit 5; }

    AGENT_JSON="$(cat "${AGENT_OUTPUT}")"
    for category in adapter_failure_modes recurring_intents prior_art_clusters topic_coverage_gaps; do
      items=$(echo "${AGENT_JSON}" | jq --arg c "${category}" '.patterns[$c] // []')
      n=$(echo "${items}" | jq 'length')
      if [ "${n}" -gt 0 ]; then
        slug=$(echo "${category}" | tr '_' '-')
        file="${DREAM_DIR}/insights/pattern-${slug}.md"
        echo "# ${category//_/ }" > "${file}"
        echo "" >> "${file}"
        echo "${items}" | jq -r '.[] | "## " + (.cluster_name // .title // .name // .topic // "") + "\n\n" + (.body // "") + "\n\n**Evidence:** " + ((.evidence_slugs // []) | join(", ")) + "\n\n**Action:** " + (.action // "") + "\n"' >> "${file}"
      fi
    done

    INPUTS_INLINE=$(jq -r '.inputs | map("\"" + . + "\"") | join(", ")' "${DREAM_DIR}/meta.json")
    INPUT_COUNT=$(jq -r '.input_count' "${DREAM_DIR}/meta.json")
    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    cat > "${DREAM_DIR}/README.md" <<EOF
---
run_id: "${RUN_ID}"
created: "${NOW}"
inputs: [${INPUTS_INLINE}]
status: "active"
supersedes: null
---

# Dream ${RUN_ID}

Cross-session patterns extracted from ${INPUT_COUNT} input sessions.

EOF
    for f in "${DREAM_DIR}/insights"/*.md; do
      [ -f "$f" ] || continue
      title=$(head -1 "$f" | sed 's/^# //')
      echo "- See \`insights/$(basename "$f")\` — ${title}" >> "${DREAM_DIR}/README.md"
    done

    inputs_with_hash="[]"
    while IFS= read -r slug; do
      hash=$(jq -r --arg s "${slug}" '.sessions[] | select(.slug == $s) | .content_sha256 // ""' "${MANIFEST}")
      inputs_with_hash=$(echo "${inputs_with_hash}" | jq --arg s "${slug}" --arg h "${hash}" '. + [{slug: $s, content_sha256: $h}]')
    done < <(jq -r '.inputs[]' "${DREAM_DIR}/meta.json")
    jq -nc --argjson i "${inputs_with_hash}" '{inputs: ($i | map(.slug)), input_hashes: $i}' > "${DREAM_DIR}/sources.json"

    node "${REPO_ROOT}/lib/memory/ledger.mjs" --reset --run-id "${RUN_ID}" --ledger "${LEDGER}"
    bash "${SCRIPT_DIR}/memory_reindex.sh"

    echo "{\"run_id\":\"${RUN_ID}\",\"path\":\"docs/dreams/${RUN_ID}\"}"
    ;;
  *)
    echo "dream_run: must specify --resolve-only|--mint-only|--finalize" >&2
    exit 2
    ;;
esac
```

- [ ] **Step 4: 실행 권한**

```bash
chmod +x scripts/dream_run.sh
```

- [ ] **Step 5: 통과 확인**

```
bats tests/research-engine/dream.test.sh
```

Expected: PASS — 4/4.

- [ ] **Step 6: Commit**

```bash
git add scripts/dream_run.sh tests/research-engine/dream.test.sh tests/research-engine/fixtures/dream-input-sessions
git commit -m "feat(dream): dream_run.sh — D1·D2·D4-D7 shell wrapper + 4 bats"
```

---

## Task 13: commands/dream.md — `/dream` 슬래시 시퀀스

**Files:**
- Create: `commands/dream.md`

- [ ] **Step 1: 슬래시 명세 작성**

`commands/dream.md`:

```markdown
# `/dream`

Extract cross-session patterns from past `/research` sessions, write readonly insights to `docs/dreams/<run-id>/`.

## Inputs

- `/dream` — default: 최근 dream 이후 누적 전체 (`dream-ledger.sessions_since_last_dream`)
- `/dream --since=14d` — 최근 14일 내 세션
- `/dream --slugs=a,b,c` — 명시 슬러그 (콤마 구분)
- `/dream --bench=<bench-run-id>` — bench 결과를 입력 데이터로 추가 (옵션)

## Constants

- Plugin root: `/home/taejin/.claude/plugins/cache/gprecious-marketplace/research-engine/0.10.0`
- MANIFEST = `research/_index/manifest.json`
- LEDGER = `research/_index/dream-ledger.json`

## Pipeline

### D1 — Resolve inputs

```bash
bash "${PLUGIN_ROOT}/scripts/dream_run.sh" --resolve-only [--slugs ... | --since ...]
```

If exit non-zero with "not enough sessions" — STOP and tell the user. Do not mint a dream from <2 sessions.

### D2 — Mint run_id + directory

```bash
MINT_JSON=$(bash "${PLUGIN_ROOT}/scripts/dream_run.sh" --mint-only [args])
RUN_ID=$(echo "${MINT_JSON}" | jq -r '.run_id')
```

Creates `docs/dreams/<RUN_ID>/{meta.json,insights/}`.

### D3 — Dispatch dream-extractor (Agent tool)

Prepare input JSON:

```bash
MANIFEST_EXCERPT=$(jq --argjson resolved "$(echo "${MINT_JSON}" | jq '.resolved')" '
  {sessions: [.sessions[] | select(.slug as $s | $resolved | index($s))]}
' "${MANIFEST}")

INTENT_DIST=$(echo "${MANIFEST_EXCERPT}" | jq '
  {
    by_focus: ([.sessions[].intent.focus] | group_by(.) | map({(.[0]): length}) | add),
    by_audience: ([.sessions[].intent.audience_level] | group_by(.) | map({(.[0]): length}) | add)
  }')

AGENT_INPUT=$(jq -nc \
  --arg run_id "${RUN_ID}" \
  --argjson session_paths "$(echo "${MANIFEST_EXCERPT}" | jq '[.sessions[].path]')" \
  --argjson manifest_excerpt "${MANIFEST_EXCERPT}" \
  --argjson intent_distribution "${INTENT_DIST}" \
  '{run_id: $run_id, session_paths: $session_paths, manifest_excerpt: $manifest_excerpt, intent_distribution: $intent_distribution, bench_excerpt: null}')
```

Dispatch via Agent tool:

```
Agent(
  description: "dream-extractor for <RUN_ID>",
  subagent_type: "research-engine:dream-extractor",
  prompt: "You are dispatched as the dream-extractor subagent for run <RUN_ID>.\n\nInputs:\n  <AGENT_INPUT>\n\nReturn a single fenced JSON block per the contract in agents/dream-extractor.md."
)
```

Save agent's JSON to `/tmp/dream-output-${RUN_ID}.json`.

### D4–D7 — Finalize

```bash
bash "${PLUGIN_ROOT}/scripts/dream_run.sh" --finalize \
  --run-id "${RUN_ID}" \
  --agent-output "/tmp/dream-output-${RUN_ID}.json"
```

Splits patterns into `insights/pattern-*.md`, writes `README.md` (frontmatter status=active), writes `sources.json` (input slugs + sha256), resets `dream-ledger.json`, runs `memory_reindex.sh`.

### D8 — Final user message

```
📄 docs/dreams/<RUN_ID>/README.md
2줄 TL;DR (from strongest pattern)
N개 insight 파일 생성됨 — 부적절한 것은 README frontmatter의 status를 discarded로 변경하세요.
```

## Failure handling

- **Agent returns non-JSON / malformed**: 1회 자동 재시도 + 엄격한 prompt. 2회 실패 → `docs/dreams/<RUN_ID>/FAILED.md` 작성, ledger 미업데이트, 종료.
- **빈 patterns**: 정상 완료, README.md에 "no significant patterns found across N inputs" 노트, ledger 업데이트.
- **타임아웃 5분 초과** (기본 어댑터 타임아웃 동일): JSON 파싱 실패와 동일 처리.
```

- [ ] **Step 2: Commit**

```bash
git add commands/dream.md
git commit -m "feat(dream): /dream 슬래시 명세 — D1~D8 시퀀스 + 실패 처리"
```

---

## Task 14: `/research-followup` OCC precondition (RED → GREEN → COMMIT)

**Files:**
- Modify: `commands/research-followup.md`
- Create: `tests/research-engine/research-followup-occ.test.sh`

- [ ] **Step 1: RED bats**

`tests/research-engine/research-followup-occ.test.sh`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  TMP_HOME="$(mktemp -d)"
  SLUG="2026-05-01-fixture-a"
  mkdir -p "${TMP_HOME}/research/${SLUG}"
  cat > "${TMP_HOME}/research/${SLUG}/session.md" <<'EOF'
# session log

- initial entry
EOF
  export REPO_ROOT TMP_HOME SLUG
}

teardown() {
  rm -rf "${TMP_HOME}"
}

@test "OCC: sha256 일치 → write 가능" {
  cd "${TMP_HOME}"
  expected=$(sha256sum "${TMP_HOME}/research/${SLUG}/session.md" | awk '{print $1}')
  actual=$(sha256sum "${TMP_HOME}/research/${SLUG}/session.md" | awk '{print $1}')
  [ "$expected" = "$actual" ]
}

@test "OCC: 동시 수정 시뮬레이션 → mismatch 감지" {
  cd "${TMP_HOME}"
  before=$(sha256sum "${TMP_HOME}/research/${SLUG}/session.md" | awk '{print $1}')
  echo "- concurrent edit" >> "${TMP_HOME}/research/${SLUG}/session.md"
  after=$(sha256sum "${TMP_HOME}/research/${SLUG}/session.md" | awk '{print $1}')
  [ "$before" != "$after" ]
}

@test "OCC: atomic rename — session.md.tmp 부분 쓰기 시 session.md 불변" {
  cd "${TMP_HOME}"
  original_hash=$(sha256sum "${TMP_HOME}/research/${SLUG}/session.md" | awk '{print $1}')
  # 부분 쓰기 시뮬레이션
  echo "partial" > "${TMP_HOME}/research/${SLUG}/session.md.tmp"
  # rename 안 함 — session.md 그대로
  current=$(sha256sum "${TMP_HOME}/research/${SLUG}/session.md" | awk '{print $1}')
  [ "$original_hash" = "$current" ]
}
```

- [ ] **Step 2: 테스트 실행 (PASS 예상 — hash 계산 자체는 가능)**

```
bats tests/research-engine/research-followup-occ.test.sh
```

Expected: PASS — 3/3 (hash 비교 + atomic rename invariant).

- [ ] **Step 3: commands/research-followup.md OCC 섹션 추가**

`commands/research-followup.md`의 session.md write 단계 직전에 추가:

```markdown
### OCC precondition (concurrent write protection)

Before appending to `research/<slug>/session.md`:

1. Compute expected hash:
   ```bash
   expected_hash=$(sha256sum research/<slug>/session.md | awk '{print $1}')
   ```

2. Generate new content (may take seconds while LLM thinks).

3. Just before writing, recompute:
   ```bash
   actual_hash=$(sha256sum research/<slug>/session.md | awk '{print $1}')
   ```

4. If `expected_hash != actual_hash`:
   - Re-read current session.md, regenerate the new content using current state as context (1 auto-retry).
   - On second mismatch: STOP and tell the user "concurrent edit detected on `<slug>/session.md` — please re-run /research-followup after resolving the conflict manually."

5. Atomic write:
   ```bash
   cat session.md new_content > session.md.tmp
   mv session.md.tmp session.md
   ```

This OCC protects against multi-pane (`cmux:cmux-orchestrator`) scenarios where two `/research-followup` calls could race on the same session.
```

- [ ] **Step 4: 통과 확인**

```
bats tests/research-engine/research-followup-occ.test.sh
```

Expected: PASS — 3/3.

- [ ] **Step 5: Commit**

```bash
git add commands/research-followup.md tests/research-engine/research-followup-occ.test.sh
git commit -m "feat(research-followup): sha256 OCC precondition + 1회 자동 재시도"
```

---

## Task 15: `/bench` post-hook 제안

**Files:**
- Modify: `commands/bench.md`

- [ ] **Step 1: post-hook 줄 추가**

`commands/bench.md` report.md 작성 후 사용자에게 알림 직전에 추가:

```markdown
### Dream suggestion (after report.md is written)

If `research/_index/dream-ledger.json` exists and `last_dream_at < bench.started_at`, append this line to the final user message:

```bash
if [ -f "research/_index/dream-ledger.json" ]; then
  last_dream=$(jq -r '.last_dream_at // ""' research/_index/dream-ledger.json)
  bench_started=$(jq -r '.started_at // ""' "bench/runs/${BENCH_RUN_ID}/meta.json" 2>/dev/null || echo "")
  if [ -z "${last_dream}" ] || [ "${last_dream}" \< "${bench_started}" ]; then
    echo "💡 새 bench 결과: /dream --bench=${BENCH_RUN_ID} 로 어댑터 약점을 인사이트로 전환할 수 있어요."
  fi
fi
```

자동 트리거는 *하지 않는다* — 사용자가 명시 호출해야 함.
```

- [ ] **Step 2: Commit**

```bash
git add commands/bench.md
git commit -m "feat(bench): post-hook /dream 제안 메시지 (자동 트리거 없음)"
```

---

## Task 16: dream-e2e — 풀 사이클 + status 편집 (RED → GREEN → COMMIT)

**Files:**
- Create: `tests/research-engine/dream-e2e.test.sh`
- Create: `tests/research-engine/fixtures/dreams/active/README.md`
- Create: `tests/research-engine/fixtures/dreams/discarded/README.md`

- [ ] **Step 1: dream fixture 생성**

`tests/research-engine/fixtures/dreams/active/README.md`:

```markdown
---
run_id: "drm_active-fixture"
created: "2026-04-01T10:00:00+09:00"
inputs: ["fixture-a", "fixture-b"]
status: "active"
supersedes: null
---
# active dream fixture
```

`tests/research-engine/fixtures/dreams/discarded/README.md`:

```markdown
---
run_id: "drm_discarded-fixture"
created: "2026-04-02T10:00:00+09:00"
inputs: ["fixture-a", "fixture-b"]
status: "discarded"
supersedes: null
---
# discarded dream fixture
```

- [ ] **Step 2: bats e2e**

`tests/research-engine/dream-e2e.test.sh`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  TMP_HOME="$(mktemp -d)"
  cp -r "${REPO_ROOT}/tests/research-engine/fixtures/dream-input-sessions"/. "${TMP_HOME}/"
  mkdir -p "${TMP_HOME}/docs/dreams/drm_active-fixture"
  mkdir -p "${TMP_HOME}/docs/dreams/drm_discarded-fixture"
  cp "${REPO_ROOT}/tests/research-engine/fixtures/dreams/active/README.md" "${TMP_HOME}/docs/dreams/drm_active-fixture/"
  cp "${REPO_ROOT}/tests/research-engine/fixtures/dreams/discarded/README.md" "${TMP_HOME}/docs/dreams/drm_discarded-fixture/"
  cd "${TMP_HOME}"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"
  export REPO_ROOT TMP_HOME
}

teardown() {
  rm -rf "${TMP_HOME}"
}

@test "dream e2e: memory_query는 active만 dream_insights에 포함" {
  cd "${TMP_HOME}"
  active_count=$(jq '[.dreams[] | select(.status == "active")] | length' "${TMP_HOME}/research/_index/manifest.json")
  discarded_count=$(jq '[.dreams[] | select(.status == "discarded")] | length' "${TMP_HOME}/research/_index/manifest.json")
  [ "$active_count" -ge 1 ]
  [ "$discarded_count" -ge 1 ]

  TARGET='{"input_type":"arxiv","topics":[],"intent":{"purpose":"x"}}'
  run bash "${REPO_ROOT}/scripts/memory_query.sh" --target-json "${TARGET}"
  [ "$status" -eq 0 ]
  # dream_insights 안에 discarded는 없어야 함
  ! echo "$output" | jq -r '.dream_insights[].path' | grep -q "discarded"
  # active는 있어야 함
  echo "$output" | jq -r '.dream_insights[].path' | grep -q "active"
}

@test "dream e2e: status active → discarded 편집 후 reindex → memory_query에서 제외" {
  cd "${TMP_HOME}"
  sed -i 's/status: "active"/status: "discarded"/' "${TMP_HOME}/docs/dreams/drm_active-fixture/README.md"
  bash "${REPO_ROOT}/scripts/memory_reindex.sh"

  TARGET='{"input_type":"arxiv","topics":[],"intent":{"purpose":"x"}}'
  run bash "${REPO_ROOT}/scripts/memory_query.sh" --target-json "${TARGET}"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '.dream_insights | length')" = "0" ]
}

@test "dream e2e: 풀 사이클 — mint → finalize → ledger 리셋 + manifest dreamed_in 업데이트" {
  cd "${TMP_HOME}"
  ALL_SLUGS=$(jq -r '.sessions | map(.slug) | join(",")' "${TMP_HOME}/research/_index/manifest.json")

  MINT=$(bash "${REPO_ROOT}/scripts/dream_run.sh" --mint-only --slugs "${ALL_SLUGS}")
  RUN_ID=$(echo "${MINT}" | jq -r '.run_id')

  cat > /tmp/dream-output-e2e.json <<EOF
{
  "run_id": "${RUN_ID}",
  "input_count": 3,
  "patterns": {
    "recurring_intents": [
      { "cluster_name": "agent memory", "evidence_slugs": ["2026-05-10-dream-input-a","2026-05-11-dream-input-b"], "body": "agent memory 반복 주제", "action": "topic boost" }
    ]
  },
  "failures": []
}
EOF

  bash "${REPO_ROOT}/scripts/dream_run.sh" --finalize --run-id "${RUN_ID}" --agent-output /tmp/dream-output-e2e.json

  [ -f "${TMP_HOME}/docs/dreams/${RUN_ID}/README.md" ]
  [ -f "${TMP_HOME}/docs/dreams/${RUN_ID}/insights/pattern-recurring-intents.md" ]
  grep -q 'status: "active"' "${TMP_HOME}/docs/dreams/${RUN_ID}/README.md"

  [ "$(jq -r '.last_dream_run_id' "${TMP_HOME}/research/_index/dream-ledger.json")" = "${RUN_ID}" ]
  [ "$(jq '.sessions_since_last_dream | length' "${TMP_HOME}/research/_index/dream-ledger.json")" = "0" ]

  count=$(jq --arg r "${RUN_ID}" '[.sessions[] | select(.dreamed_in | index($r))] | length' "${TMP_HOME}/research/_index/manifest.json")
  [ "$count" = "3" ]
}
```

- [ ] **Step 3: 통과 확인**

```
bats tests/research-engine/dream-e2e.test.sh
```

Expected: PASS — 3/3.

- [ ] **Step 4: Commit**

```bash
git add tests/research-engine/dream-e2e.test.sh tests/research-engine/fixtures/dreams
git commit -m "test(dream): e2e — active/discarded + 풀 사이클 + dreamed_in 역색인"
```

---

## Task 17: package.json — test:bats 갱신

**Files:**
- Modify: `package.json`

- [ ] **Step 1: test:bats 확장**

기존 `package.json`:

```json
"test:bats": "bats tests/research-engine/spec.test.sh tests/research-engine/design.test.sh tests/research-engine/deploy.test.sh",
```

새로:

```json
"test:bats": "bats tests/research-engine/spec.test.sh tests/research-engine/design.test.sh tests/research-engine/deploy.test.sh tests/research-engine/memory.test.sh tests/research-engine/dream.test.sh tests/research-engine/research-with-memory.test.sh tests/research-engine/dream-e2e.test.sh tests/research-engine/research-followup-occ.test.sh",
```

- [ ] **Step 2: 전체 테스트 통과 확인**

```bash
npx vitest run lib/memory/
npm run test:bats
```

Expected: 모든 PASS.

- [ ] **Step 3: Commit**

```bash
git add package.json
git commit -m "chore: test:bats에 memory + dream + followup bats 5개 추가"
```

---

## Task 18: Manual e2e — 실제 /research → /dream 풀 흐름 검증

**Files:** (검증만)

- [ ] **Step 1: 기존 80여 세션 manifest 인식 확인**

```bash
cd /home/taejin/projects/research-engine
bash scripts/memory_reindex.sh
jq '.sessions | length' research/_index/manifest.json
```

Expected: 80 내외 (실제 세션 수). 0이면 buildSessionEntry 디버그.

- [ ] **Step 2: 기존 세션 파일 mtime 불변 확인**

```bash
stat -c "%Y %n" research/2026-04-17-claude-opus-47-most-powerful-coding-mode/sources.json
bash scripts/memory_reindex.sh
stat -c "%Y %n" research/2026-04-17-claude-opus-47-most-powerful-coding-mode/sources.json
```

Expected: 두 줄 동일.

- [ ] **Step 3: 실제 /research 실행 + cache/memory.json 확인**

```
/research <some-new-target-url>
```

진행 후:

```bash
cat research/<new-slug>/cache/memory.json | jq '.similar_sessions | length'
```

Expected: 1 이상.

- [ ] **Step 4: ledger 카운터 확인**

```bash
jq '.sessions_since_last_dream | length' research/_index/dream-ledger.json
```

- [ ] **Step 5: /dream 실행**

```
/dream
```

5개 미만이면 "not enough sessions" 에러 → 더 누적 후 재시도. 5개 이상이면 dream artifact 생성:

```bash
ls docs/dreams/
cat docs/dreams/drm_*/README.md | head -40
```

- [ ] **Step 6: 다음 /research가 dream insights 받는지 확인**

```
/research <another-new-target>
```

```bash
cat research/<another-slug>/cache/memory.json | jq '.dream_insights | length'
```

Expected: 1 이상.

- [ ] **Step 7: 최종 검증 commit**

```bash
git commit --allow-empty -m "verify: end-to-end manual check — research → reindex → dream → next research"
```

---

## Self-Review

**Spec coverage:**
- §4.1 manifest schema → Tasks 3, 5
- §4.2 ledger schema → Task 4
- §4.3 dreams artifact layout → Tasks 11, 12, 13
- §4.4 sources.json 신규 필드 → Task 8
- §4.5 메타데이터 책임 매트릭스 → Tasks 5, 8, 10, 12
- §5.1 /research 시퀀스 → Tasks 7 (Stage 2), 8 (5.2), 9 (Stage 4), 10 (5.8)
- §5.2 /dream 시퀀스 → Tasks 11, 12, 13
- §5.3 /bench post-hook → Task 15
- §5.4 reindex 호출 시점 3개 → Tasks 5 (명시), 10 (Stage 5.8), 12 (D7)
- §6.1 컴포넌트 인벤토리 → 모든 task의 Files 섹션
- §6.2 기존 파일 수정 → Tasks 7-10, 14, 15, 17
- §6.3 git ignore vs commit → 본 plan은 _index와 dreams를 git commit (별도 .gitignore 변경 없음)
- §7 에러 처리 (manifest/ledger fail-soft, OCC, dream agent 실패, 5회 반복 방지) → Tasks 5, 6, 13, 14
- §8 테스트 invariants → memory.test.sh, dream.test.sh, dream-e2e.test.sh, research-with-memory.test.sh, research-followup-occ.test.sh 5개 파일 분산
- §10 Acceptance criteria → Task 18 manual e2e가 모두 검증

**Placeholder scan:** "TBD", "implement later", "add error handling" 없음. 모든 코드 블록 runnable.

**Type/symbol consistency:** `buildSessionEntry`, `buildDreamEntry`, `buildManifest`, `emptyLedger`, `bumpAfterResearch`, `shouldSuggest`, `markSuggested`, `resetAfterDream`, `rebuildFromManifest`, `scoreSession`, `topK`, `tokenize` — 함수명·시그니처가 정의 task와 호출 task에서 일관.

**Security:** Node child process는 `execFileSync` 사용 (Task 3). shell 인라인 jq/sha256sum은 args가 항상 fixed string 또는 controlled JSON — 인젝션 표면 없음.
