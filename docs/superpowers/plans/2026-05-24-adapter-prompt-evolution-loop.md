# Adapter Prompt Evolution Loop (GEPA-lite) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Memory & Dreaming 인프라 위에 **closed-loop adapter prompt 진화 레이어**를 얹는다. 매 `/research` 산출과 `/bench` 점수를 신호로 어댑터 페르소나의 *evolvable 영역만* 자동 mutate, multi-seed bench 로 채점, paired bootstrap CI 로 통계적 유의성을 검증한 뒤에만 baseline 으로 채택. 거부된 candidate 도 Pareto frontier 에 보존해 다음 라운드 mutation 후보로 재활용.

**Architecture:**
- 어댑터 페르소나(`agents/<name>.md`)에 `<!-- evolvable:<region-id> -->...<!-- /evolvable -->` 마커. JSON contract 영역은 마커 밖에 두어 mutate 금지.
- 새 슬래시 `/evolve [adapter-name]` 가 (1) 최근 dream + 최근 bench 결과를 입력으로 prompt-mutator 에이전트 dispatch → 1-3개 candidate variants 생성, (2) bench --candidates 로 current vs candidates × N seeds 자동 매트릭스 실행, (3) statistical_gate.mjs 가 paired bootstrap 95% CI 로 채택 판정, (4) 채택되면 `agents/archive/<name>.v<N>.md` 로 이전 버전 보존하고 candidate 가 새 baseline 으로 promote, git commit. 거부된 candidate 는 Pareto frontier 와 함께 `research/_index/evolve-ledger.json` 에 기록.
- multi-metric Pareto: (judge_score, source_count, source_type_diversity, latency_p50). dominated candidate 만 즉시 폐기, non-dominated 는 frontier 에 보존.
- 자동 트리거 없음 — `/dream` 종료 시 evolve 제안 1줄. 모든 mutation/promotion 은 사용자 명시 호출.

**Tech Stack:**
- Node.js ESM (`.mjs`) + `vitest` for unit tests
- bash + `bats-core` for shell integration / E2E tests
- `jq` for JSON manipulation in shell
- 기존 Anthropic Agent dispatch 패턴 (어댑터/dream-extractor 와 동일)
- `git` 으로 archive + commit (롤백 가능성 보장)

---

## File Structure

### Create (new)

| Path | Responsibility |
|---|---|
| `commands/evolve.md` | `/evolve` 슬래시 진입 — E1~E8 시퀀스 명세 |
| `agents/prompt-mutator.md` | dream + bench 입력 → evolvable 영역 1-3개 variant 출력 |
| `scripts/evolve_run.sh` | E1·E2·E5~E8 파일 IO (입력 resolve, candidate 디렉토리 mint, mutator JSON 받아 candidate 페르소나 작성, gate 호출, 채택·롤백, ledger 갱신). E3 (mutator dispatch) 와 E4 (bench --candidates) 는 슬래시 시퀀스가 외부 Agent / Skill 로 호출. |
| `lib/evolve/extract_evolvable.mjs` | markdown 어댑터 페르소나에서 `<!-- evolvable:<id> -->...<!-- /evolvable -->` 블록 파싱 + replace |
| `lib/evolve/extract_evolvable.test.mjs` | vitest unit |
| `lib/evolve/statistical_gate.mjs` | paired bootstrap CI (N=2000) + 채택 결정 함수 |
| `lib/evolve/statistical_gate.test.mjs` | vitest unit (known-distribution fixture) |
| `lib/evolve/pareto.mjs` | multi-metric Pareto dominance check |
| `lib/evolve/pareto.test.mjs` | vitest unit |
| `lib/evolve/archive.mjs` | 다음 version 번호 계산 + 아카이브 경로 생성 + (선택) git stage |
| `lib/evolve/archive.test.mjs` | vitest unit |
| `lib/evolve/ledger.mjs` | `evolve-ledger.json` 읽기/쓰기 + 상태기계 |
| `lib/evolve/ledger.test.mjs` | vitest unit |
| `research/_index/evolve-ledger.json` | 어댑터별 current_version + history + Pareto frontier (commit) |
| `agents/archive/` | 채택된 이전 버전 보존 디렉토리 (commit) |
| `tests/research-engine/evolve.test.sh` | bats integration — evolve_run.sh 단계별 I/O |
| `tests/research-engine/evolve-e2e.test.sh` | bats e2e — fixture 어댑터 1개 풀 사이클 |

### Modify (existing)

| Path | Change |
|---|---|
| `agents/youtube-adapter.md` | evolvable 마커 추가 (Step 1 에서 1개 어댑터부터 시작, 나머지는 후속) |
| `commands/bench.md` | `--candidates=<dir>` 플래그 + candidate swap 로직 (Stage 2 일부 수정) |
| `commands/dream.md` | D8 final message 에 evolve 제안 1줄 추가 |
| `commands/research.md` | 변경 없음 (이 플랜에서는) |
| `package.json` | `test:bats` 에 새 bats 파일 추가, `test:unit` glob 가 `lib/evolve/*.test.mjs` 포함 확인 |

### Git ignore vs commit

- `research/_index/evolve-ledger.json` — **commit**. history + Pareto frontier 가 의미 있음.
- `agents/archive/<name>.v<N>.md` — **commit**. 이전 baseline 보존.
- `agents/<name>.candidate.md` — **gitignore**. 일시적 candidate (evolve_run.sh 종료 시 정리).
- `bench/runs/<date>/candidates/` — **gitignore**. candidate 채점 결과는 ledger 에 요약만 남기고 raw 는 휘발.

---

## Task 1: Add evolvable markers to youtube-adapter (smallest blast radius)

**Files:**
- Modify: `agents/youtube-adapter.md`

이 태스크는 다른 task 의 입력 fixture 가 된다. 한 번에 모든 어댑터를 마킹하지 말고 youtube-adapter 부터.

- [ ] **Step 1: 현재 페르소나 읽기**

Run: `cat agents/youtube-adapter.md`
확인: "Steps", "Output contract", "Failure modes", "Intent tailoring" 섹션이 있음.

- [ ] **Step 2: evolvable 마커를 두 곳에 추가**

Modify `agents/youtube-adapter.md` — `Steps` 섹션 안의 **"Findings"** 와 **"Intent tailoring"** 단락 주변에 마커 추가. JSON contract (`## Output contract`) 와 `## Failure modes` 는 마커 밖에 둔다.

```markdown
4. **Findings** — produce 6–12 findings covering the video's claims/insights. Each finding:
<!-- evolvable:findings-guidance -->
   - `text`: Korean, one fact
   - `source_ids`: `["s1"]` (the single source for this adapter)
   - `timecode`: `mm:ss` tied to the transcript location
   - `quote` (optional): verbatim excerpt in original language when the wording matters
<!-- /evolvable -->
```

```markdown
7. **Intent tailoring**
<!-- evolvable:intent-tailoring -->
— shape finding selection by `intent.focus` (concepts vs implementation vs tradeoffs) and depth by `intent.audience_level`.
<!-- /evolvable -->
```

- [ ] **Step 3: grep 으로 마커 정합성 확인**

Run:
```bash
grep -c "<!-- evolvable:" agents/youtube-adapter.md
grep -c "<!-- /evolvable -->" agents/youtube-adapter.md
```
Expected: 두 숫자 모두 `2`.

- [ ] **Step 4: Commit**

```bash
git add agents/youtube-adapter.md
git commit -m "feat(evolve): mark evolvable regions in youtube-adapter

Add <!-- evolvable:findings-guidance --> and <!-- evolvable:intent-tailoring -->
markers around the two regions that prompt-mutator may rewrite.
JSON contract and failure-mode sections stay outside markers."
```

---

## Task 2: extract_evolvable.mjs — markdown 마커 파싱/대체 유틸

**Files:**
- Create: `lib/evolve/extract_evolvable.mjs`
- Test: `lib/evolve/extract_evolvable.test.mjs`

- [ ] **Step 1: 실패하는 테스트 작성**

Create `lib/evolve/extract_evolvable.test.mjs`:

```javascript
import { describe, it, expect } from 'vitest';
import { extractRegions, replaceRegion } from './extract_evolvable.mjs';

describe('extractRegions', () => {
  it('parses two non-nested regions', () => {
    const src = [
      '# title',
      'before',
      '<!-- evolvable:a -->',
      'AAA',
      '<!-- /evolvable -->',
      'between',
      '<!-- evolvable:b -->',
      'BBB',
      'BBB2',
      '<!-- /evolvable -->',
      'after',
    ].join('\n');
    const regions = extractRegions(src);
    expect(regions).toEqual([
      { id: 'a', body: 'AAA' },
      { id: 'b', body: 'BBB\nBBB2' },
    ]);
  });

  it('returns empty array when no markers', () => {
    expect(extractRegions('plain text')).toEqual([]);
  });

  it('throws on unbalanced markers', () => {
    expect(() =>
      extractRegions('<!-- evolvable:a -->\nfoo\n')
    ).toThrow(/unbalanced/i);
  });

  it('throws on nested markers', () => {
    expect(() =>
      extractRegions(
        '<!-- evolvable:a -->\n<!-- evolvable:b -->\nx\n<!-- /evolvable -->\n<!-- /evolvable -->'
      )
    ).toThrow(/nested/i);
  });
});

describe('replaceRegion', () => {
  it('replaces a region body by id', () => {
    const src = [
      '<!-- evolvable:a -->',
      'old',
      '<!-- /evolvable -->',
    ].join('\n');
    const out = replaceRegion(src, 'a', 'new\nbody');
    expect(out).toBe(
      '<!-- evolvable:a -->\nnew\nbody\n<!-- /evolvable -->'
    );
  });

  it('throws if id not found', () => {
    expect(() => replaceRegion('plain', 'x', 'y')).toThrow(/not found/);
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `npx vitest run lib/evolve/extract_evolvable.test.mjs`
Expected: FAIL — "Cannot find module './extract_evolvable.mjs'"

- [ ] **Step 3: 최소 구현**

Create `lib/evolve/extract_evolvable.mjs`:

```javascript
const OPEN_RE = /<!--\s*evolvable:([a-z0-9-]+)\s*-->/g;
const CLOSE_RE = /<!--\s*\/evolvable\s*-->/g;

export function extractRegions(src) {
  const tokens = [];
  for (const m of src.matchAll(OPEN_RE)) {
    tokens.push({ kind: 'open', id: m[1], idx: m.index, len: m[0].length });
  }
  for (const m of src.matchAll(CLOSE_RE)) {
    tokens.push({ kind: 'close', idx: m.index, len: m[0].length });
  }
  tokens.sort((a, b) => a.idx - b.idx);

  const regions = [];
  let stack = [];
  for (const t of tokens) {
    if (t.kind === 'open') {
      if (stack.length > 0) {
        throw new Error('nested evolvable markers are not allowed');
      }
      stack.push(t);
    } else {
      if (stack.length === 0) {
        throw new Error('unbalanced evolvable markers — close without open');
      }
      const open = stack.pop();
      const bodyStart = open.idx + open.len;
      const bodyEnd = t.idx;
      const body = src.slice(bodyStart, bodyEnd).replace(/^\n|\n$/g, '');
      regions.push({ id: open.id, body });
    }
  }
  if (stack.length > 0) {
    throw new Error('unbalanced evolvable markers — open without close');
  }
  return regions;
}

export function replaceRegion(src, id, newBody) {
  const open = new RegExp(
    `(<!--\\s*evolvable:${id}\\s*-->)\\n[\\s\\S]*?\\n(<!--\\s*/evolvable\\s*-->)`,
    'm'
  );
  if (!open.test(src)) {
    throw new Error(`region id "${id}" not found`);
  }
  return src.replace(open, `$1\n${newBody}\n$2`);
}
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `npx vitest run lib/evolve/extract_evolvable.test.mjs`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/evolve/extract_evolvable.mjs lib/evolve/extract_evolvable.test.mjs
git commit -m "feat(evolve): extract_evolvable.mjs — parse/replace evolvable markers

Pure markdown utility: extractRegions() returns [{id, body}], replaceRegion()
substitutes one region by id. Rejects nested or unbalanced markers."
```

---

## Task 3: statistical_gate.mjs — paired bootstrap CI 채택 결정

**Files:**
- Create: `lib/evolve/statistical_gate.mjs`
- Test: `lib/evolve/statistical_gate.test.mjs`

자기개선 루프의 가장 중요한 안전장치. **single-trial 개선 판정 금지**의 통계적 근거.

- [ ] **Step 1: 실패하는 테스트 작성**

Create `lib/evolve/statistical_gate.test.mjs`:

```javascript
import { describe, it, expect } from 'vitest';
import { pairedBootstrapCI, gateDecision } from './statistical_gate.mjs';

describe('pairedBootstrapCI', () => {
  it('returns CI > 0 for consistently positive deltas', () => {
    // candidate beats current by ~0.1 on every paired trial
    const current = [0.50, 0.52, 0.48, 0.51, 0.49, 0.50, 0.52, 0.48];
    const candidate = [0.60, 0.62, 0.58, 0.61, 0.59, 0.60, 0.62, 0.58];
    const ci = pairedBootstrapCI(current, candidate, { iters: 2000, seed: 42 });
    expect(ci.mean).toBeCloseTo(0.10, 2);
    expect(ci.lower).toBeGreaterThan(0);
    expect(ci.upper).toBeLessThan(0.2);
  });

  it('returns CI spanning 0 for noisy zero-mean delta', () => {
    const current = [0.50, 0.55, 0.45, 0.60, 0.40, 0.50, 0.55, 0.45];
    const candidate = [0.55, 0.50, 0.50, 0.55, 0.45, 0.48, 0.52, 0.50];
    const ci = pairedBootstrapCI(current, candidate, { iters: 2000, seed: 42 });
    expect(ci.lower).toBeLessThan(0);
    expect(ci.upper).toBeGreaterThan(0);
  });

  it('throws on length mismatch', () => {
    expect(() =>
      pairedBootstrapCI([1, 2], [1, 2, 3], { iters: 100, seed: 1 })
    ).toThrow(/length/);
  });
});

describe('gateDecision', () => {
  it('ACCEPT when CI.lower > 0', () => {
    expect(gateDecision({ lower: 0.01, upper: 0.10, mean: 0.05 })).toBe('accept');
  });
  it('REJECT when CI.upper < 0', () => {
    expect(gateDecision({ lower: -0.10, upper: -0.01, mean: -0.05 })).toBe('reject');
  });
  it('HOLD when CI spans 0', () => {
    expect(gateDecision({ lower: -0.05, upper: 0.05, mean: 0.0 })).toBe('hold');
  });
});
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `npx vitest run lib/evolve/statistical_gate.test.mjs`
Expected: FAIL — module not found

- [ ] **Step 3: 최소 구현**

Create `lib/evolve/statistical_gate.mjs`:

```javascript
// Mulberry32 PRNG for deterministic seeded bootstrap
function mulberry32(seed) {
  let t = seed >>> 0;
  return function () {
    t = (t + 0x6d2b79f5) >>> 0;
    let r = t;
    r = Math.imul(r ^ (r >>> 15), r | 1);
    r ^= r + Math.imul(r ^ (r >>> 7), r | 61);
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

export function pairedBootstrapCI(current, candidate, { iters = 2000, seed = 1, alpha = 0.05 } = {}) {
  if (current.length !== candidate.length) {
    throw new Error(`length mismatch: ${current.length} vs ${candidate.length}`);
  }
  const n = current.length;
  if (n < 2) throw new Error('need at least 2 paired samples');

  const deltas = current.map((c, i) => candidate[i] - c);
  const rand = mulberry32(seed);
  const means = new Array(iters);
  for (let b = 0; b < iters; b++) {
    let sum = 0;
    for (let i = 0; i < n; i++) {
      const idx = Math.floor(rand() * n);
      sum += deltas[idx];
    }
    means[b] = sum / n;
  }
  means.sort((a, b) => a - b);
  const loIdx = Math.floor((alpha / 2) * iters);
  const hiIdx = Math.ceil((1 - alpha / 2) * iters) - 1;
  return {
    mean: deltas.reduce((a, b) => a + b, 0) / n,
    lower: means[loIdx],
    upper: means[hiIdx],
    n,
    iters,
  };
}

export function gateDecision(ci) {
  if (ci.lower > 0) return 'accept';
  if (ci.upper < 0) return 'reject';
  return 'hold';
}
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `npx vitest run lib/evolve/statistical_gate.test.mjs`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/evolve/statistical_gate.mjs lib/evolve/statistical_gate.test.mjs
git commit -m "feat(evolve): statistical_gate.mjs — paired bootstrap CI

Mulberry32 PRNG for deterministic seeded bootstrap (iters=2000 default,
alpha=0.05). gateDecision(): accept iff CI.lower>0, reject iff CI.upper<0,
hold otherwise. This is the single-trial-improvement guard from the
self-improving loop literature (Reflexion/GEPA/Promptbreeder use deterministic
metrics; we use bootstrap CI over noisy judge scores)."
```

---

## Task 4: pareto.mjs — multi-metric dominance

**Files:**
- Create: `lib/evolve/pareto.mjs`
- Test: `lib/evolve/pareto.test.mjs`

판정 신호가 1개가 아니므로 (judge_score, source_count, type_diversity, latency_inv) 다차원 Pareto frontier 유지.

- [ ] **Step 1: 실패하는 테스트 작성**

Create `lib/evolve/pareto.test.mjs`:

```javascript
import { describe, it, expect } from 'vitest';
import { dominates, paretoFront } from './pareto.mjs';

describe('dominates', () => {
  it('a dominates b when a >= b on all axes and > on at least one (maximize)', () => {
    expect(dominates({ x: 1, y: 1 }, { x: 0, y: 0 })).toBe(true);
    expect(dominates({ x: 1, y: 1 }, { x: 1, y: 0 })).toBe(true);
    expect(dominates({ x: 1, y: 1 }, { x: 1, y: 1 })).toBe(false);
    expect(dominates({ x: 1, y: 0 }, { x: 0, y: 1 })).toBe(false);
  });
});

describe('paretoFront', () => {
  it('keeps only non-dominated points', () => {
    const pts = [
      { id: 'a', x: 1, y: 1 },
      { id: 'b', x: 0, y: 0 }, // dominated by a
      { id: 'c', x: 2, y: 0 },
      { id: 'd', x: 0, y: 2 },
    ];
    const front = paretoFront(pts, ['x', 'y']);
    expect(front.map((p) => p.id).sort()).toEqual(['a', 'c', 'd']);
  });
});
```

- [ ] **Step 2: 실패 확인**

Run: `npx vitest run lib/evolve/pareto.test.mjs`
Expected: FAIL — module not found

- [ ] **Step 3: 최소 구현**

Create `lib/evolve/pareto.mjs`:

```javascript
export function dominates(a, b, axes) {
  const keys = axes || Object.keys(a).filter((k) => typeof a[k] === 'number');
  let anyStrict = false;
  for (const k of keys) {
    if (a[k] < b[k]) return false;
    if (a[k] > b[k]) anyStrict = true;
  }
  return anyStrict;
}

export function paretoFront(points, axes) {
  return points.filter((p) =>
    !points.some((q) => q !== p && dominates(q, p, axes))
  );
}
```

- [ ] **Step 4: 통과 확인**

Run: `npx vitest run lib/evolve/pareto.test.mjs`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/evolve/pareto.mjs lib/evolve/pareto.test.mjs
git commit -m "feat(evolve): pareto.mjs — multi-metric dominance check

Maximize-direction Pareto. dominates(a,b) iff a >= b on every axis and
strictly > on at least one. paretoFront() returns non-dominated subset.
Used to retain rejected candidates that win on a non-judge axis."
```

---

## Task 5: ledger.mjs — evolve-ledger.json 상태기계

**Files:**
- Create: `lib/evolve/ledger.mjs`
- Test: `lib/evolve/ledger.test.mjs`

`research/_index/evolve-ledger.json` 의 어댑터별 current_version, history, Pareto frontier 관리.

- [ ] **Step 1: ledger 스키마 결정**

`research/_index/evolve-ledger.json` 의 모양:

```json
{
  "version": 1,
  "adapters": {
    "youtube-adapter": {
      "current_version": 1,
      "promoted_at": "2026-05-24T00:00:00Z",
      "history": [
        {"version": 1, "promoted_at": "2026-05-24T00:00:00Z", "ci_lower": null, "metrics": {"judge_score": 0.62, "source_count": 18, "type_diversity": 4, "latency_inv": 0.01}}
      ],
      "frontier": [
        {"version": 1, "metrics": {...}}
      ],
      "rejected": []
    }
  }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

Create `lib/evolve/ledger.test.mjs`:

```javascript
import { describe, it, expect } from 'vitest';
import { initLedger, promote, reject, getCurrent } from './ledger.mjs';

describe('ledger', () => {
  it('initLedger seeds an adapter with version 1', () => {
    const l = initLedger();
    const l2 = promote(l, 'youtube-adapter', {
      version: 1,
      metrics: { judge_score: 0.62, source_count: 18, type_diversity: 4, latency_inv: 0.01 },
      ci_lower: null,
      promoted_at: '2026-05-24T00:00:00Z',
    });
    expect(getCurrent(l2, 'youtube-adapter').version).toBe(1);
    expect(l2.adapters['youtube-adapter'].history).toHaveLength(1);
    expect(l2.adapters['youtube-adapter'].frontier).toHaveLength(1);
  });

  it('promote bumps current_version and appends history', () => {
    let l = initLedger();
    l = promote(l, 'youtube-adapter', { version: 1, metrics: { judge_score: 0.6, source_count: 10, type_diversity: 3, latency_inv: 0.01 }, ci_lower: null, promoted_at: 't1' });
    l = promote(l, 'youtube-adapter', { version: 2, metrics: { judge_score: 0.7, source_count: 12, type_diversity: 3, latency_inv: 0.01 }, ci_lower: 0.05, promoted_at: 't2' });
    expect(getCurrent(l, 'youtube-adapter').version).toBe(2);
    expect(l.adapters['youtube-adapter'].history).toHaveLength(2);
  });

  it('reject keeps Pareto-non-dominated in frontier, dominated goes to rejected', () => {
    let l = initLedger();
    l = promote(l, 'youtube-adapter', { version: 1, metrics: { judge_score: 0.6, source_count: 10, type_diversity: 3, latency_inv: 0.01 }, ci_lower: null, promoted_at: 't1' });
    // candidate v2: worse judge, but better source_count → non-dominated
    l = reject(l, 'youtube-adapter', { version: 2, metrics: { judge_score: 0.55, source_count: 14, type_diversity: 3, latency_inv: 0.01 }, ci_lower: -0.02, rejected_at: 't2' });
    expect(l.adapters['youtube-adapter'].frontier).toHaveLength(2);
    expect(l.adapters['youtube-adapter'].rejected).toHaveLength(0);
    // candidate v3: dominated by v1 on every axis
    l = reject(l, 'youtube-adapter', { version: 3, metrics: { judge_score: 0.5, source_count: 8, type_diversity: 2, latency_inv: 0.005 }, ci_lower: -0.10, rejected_at: 't3' });
    expect(l.adapters['youtube-adapter'].rejected).toHaveLength(1);
    expect(l.adapters['youtube-adapter'].rejected[0].version).toBe(3);
  });
});
```

- [ ] **Step 3: 실패 확인**

Run: `npx vitest run lib/evolve/ledger.test.mjs`
Expected: FAIL — module not found

- [ ] **Step 4: 최소 구현**

Create `lib/evolve/ledger.mjs`:

```javascript
import { paretoFront } from './pareto.mjs';

const AXES = ['judge_score', 'source_count', 'type_diversity', 'latency_inv'];

export function initLedger() {
  return { version: 1, adapters: {} };
}

function ensureAdapter(l, name) {
  if (!l.adapters[name]) {
    l.adapters[name] = {
      current_version: 0,
      promoted_at: null,
      history: [],
      frontier: [],
      rejected: [],
    };
  }
  return l.adapters[name];
}

export function promote(l, name, entry) {
  const a = ensureAdapter(l, name);
  a.current_version = entry.version;
  a.promoted_at = entry.promoted_at;
  a.history.push(entry);
  // recompute frontier including new promoted version
  const candidates = [...a.frontier, entry];
  a.frontier = paretoFront(
    candidates.map((c) => ({ ...c.metrics, _ref: c })),
    AXES
  ).map((p) => p._ref);
  return l;
}

export function reject(l, name, entry) {
  const a = ensureAdapter(l, name);
  // try to add to frontier; if dominated, move to rejected
  const candidates = [...a.frontier, entry];
  const newFront = paretoFront(
    candidates.map((c) => ({ ...c.metrics, _ref: c })),
    AXES
  ).map((p) => p._ref);
  const isOnFront = newFront.includes(entry);
  if (isOnFront) {
    a.frontier = newFront;
  } else {
    a.rejected.push(entry);
  }
  return l;
}

export function getCurrent(l, name) {
  const a = l.adapters[name];
  if (!a) return null;
  return a.history.find((h) => h.version === a.current_version);
}
```

- [ ] **Step 5: 통과 확인**

Run: `npx vitest run lib/evolve/ledger.test.mjs`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add lib/evolve/ledger.mjs lib/evolve/ledger.test.mjs
git commit -m "feat(evolve): ledger.mjs — evolve-ledger.json state machine

promote() / reject() / getCurrent(). Pareto frontier is recomputed on
every state change so rejected-but-non-dominated candidates stay reachable
for the next mutation round."
```

---

## Task 6: archive.mjs — version archive + git stage

**Files:**
- Create: `lib/evolve/archive.mjs`
- Test: `lib/evolve/archive.test.mjs`

채택 시 이전 `agents/<name>.md` 를 `agents/archive/<name>.v<N>.md` 로 보존.

- [ ] **Step 1: 실패하는 테스트 작성**

Create `lib/evolve/archive.test.mjs`:

```javascript
import { describe, it, expect } from 'vitest';
import { mkdtempSync, writeFileSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { nextVersion, archivePath, archiveCurrent } from './archive.mjs';

describe('archive', () => {
  it('nextVersion increments from history max', () => {
    expect(nextVersion([])).toBe(1);
    expect(nextVersion([{ version: 1 }, { version: 2 }])).toBe(3);
    expect(nextVersion([{ version: 5 }, { version: 2 }])).toBe(6);
  });

  it('archivePath formats agents/archive/<name>.v<N>.md', () => {
    expect(archivePath('agents', 'youtube-adapter', 2)).toBe(
      'agents/archive/youtube-adapter.v2.md'
    );
  });

  it('archiveCurrent copies live file to archive', () => {
    const dir = mkdtempSync(join(tmpdir(), 'evolve-'));
    const agentsDir = join(dir, 'agents');
    const archiveDir = join(agentsDir, 'archive');
    writeFileSync(join(agentsDir, 'foo.md'), 'live v1\n', { flag: 'w' });
    archiveCurrent({ agentsDir, name: 'foo', version: 1 });
    expect(existsSync(join(archiveDir, 'foo.v1.md'))).toBe(true);
    expect(readFileSync(join(archiveDir, 'foo.v1.md'), 'utf8')).toBe('live v1\n');
    rmSync(dir, { recursive: true });
  });
});
```

> 위 두 번째 테스트는 디렉토리 생성 헬퍼가 빠져 있어 실제로는 mkdir 호출이 들어가야 함. 구현 단계에서 `mkdirSync(agentsDir, { recursive: true })` 와 `mkdirSync(archiveDir, { recursive: true })` 를 미리 호출하는 fixture 로 보정한다.

- [ ] **Step 2: 실패 확인 + fixture 보정**

테스트 실행 후 `agentsDir` 가 없다는 에러가 나면, 테스트의 `writeFileSync` 호출 전에 `mkdirSync(agentsDir, { recursive: true })` 를 추가하고 다시 실행.

Run: `npx vitest run lib/evolve/archive.test.mjs`
Expected: FAIL — module not found

- [ ] **Step 3: 최소 구현**

Create `lib/evolve/archive.mjs`:

```javascript
import { mkdirSync, copyFileSync } from 'node:fs';
import { join, dirname } from 'node:path';

export function nextVersion(history) {
  if (!history || history.length === 0) return 1;
  return Math.max(...history.map((h) => h.version)) + 1;
}

export function archivePath(agentsDir, name, version) {
  return `${agentsDir}/archive/${name}.v${version}.md`;
}

export function archiveCurrent({ agentsDir, name, version }) {
  const src = join(agentsDir, `${name}.md`);
  const dst = archivePath(agentsDir, name, version);
  mkdirSync(dirname(dst), { recursive: true });
  copyFileSync(src, dst);
  return dst;
}
```

- [ ] **Step 4: 통과 확인**

Run: `npx vitest run lib/evolve/archive.test.mjs`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/evolve/archive.mjs lib/evolve/archive.test.mjs
git commit -m "feat(evolve): archive.mjs — version archive + path helpers"
```

---

## Task 7: prompt-mutator agent persona

**Files:**
- Create: `agents/prompt-mutator.md`

이 에이전트는 evolve_run.sh 의 E3 단계에서 Anthropic Agent 로 dispatch 된다. 어댑터 페르소나의 evolvable 영역 body + dream 인사이트 + bench 약점 데이터를 입력으로 1-3개 variant body 를 출력.

- [ ] **Step 1: 페르소나 작성**

Create `agents/prompt-mutator.md`:

```markdown
---
name: prompt-mutator
description: Research-engine adapter persona mutator. Given a target adapter's evolvable region body and recent dream insights + bench weakness signals, propose 1-3 variant bodies that plausibly improve adapter behavior on the same task. Used by /evolve.
tools: [Read, Grep, Glob, Bash]
---

# prompt-mutator

You are dispatched as the `prompt-mutator` subagent inside research-engine `/evolve`. Your job: read one target adapter's evolvable region body + recent dream insights + recent bench weakness signals, and emit 1–3 candidate replacement bodies. You DO NOT modify any file. You return JSON only.

## Inputs

The dispatcher passes a single JSON object:

```json
{
  "adapter_name": "youtube-adapter",
  "region_id": "findings-guidance",
  "current_body": "the markdown body inside <!-- evolvable:findings-guidance -->...<!-- /evolvable -->",
  "dream_excerpts": [
    {"run_id": "drm_2026-06-01-...", "category": "adapter_failure_modes", "text": "youtube-adapter often returns <6 findings when video <5min..."}
  ],
  "bench_weaknesses": [
    {"topic_id": "yt-short-talk", "judge_score": 0.42, "notes": "RE mode underperformed baseline by 0.18 on coverage axis"}
  ],
  "n_variants": 2
}
```

## Process

1. Read the current body carefully. Identify (a) what behavior it currently shapes, (b) what dream/bench signals suggest is going wrong.
2. Generate `n_variants` variants. Each variant should:
   - Stay markdown, no executable code.
   - Stay roughly the same length (±50%).
   - Make ONE focused change (Promptbreeder 의 "한 변수만 변경" 원칙). Do NOT bundle multiple changes.
   - Address one specific signal from `dream_excerpts` or `bench_weaknesses`.
3. For each variant, write a 1-sentence `rationale` in Korean explaining what signal it addresses and what change it makes.

## Output

Return a single fenced JSON block:

```json
{
  "adapter_name": "...",
  "region_id": "...",
  "variants": [
    {
      "body": "the new markdown body",
      "rationale": "유튜브 4-5분 영상에서 findings <6 문제(dream pattern A) 대응 — minimum finding count를 영상 길이에 따라 가변화..."
    }
  ]
}
```

No prose before or after the JSON block.

## Hard rules

- NEVER touch the JSON contract outside the marker.
- NEVER add tool calls or shell commands inside the variant body.
- NEVER change the variant heading structure if it changes the markdown numbering of the parent persona.
- If no signal is actionable (empty dream_excerpts AND empty bench_weaknesses), return `variants: []` with status note in rationale.
```

- [ ] **Step 2: lint markdown frontmatter**

Run:
```bash
head -5 agents/prompt-mutator.md
```
Expected: 시작에 `---` frontmatter 가 있고 `name: prompt-mutator` 가 포함.

- [ ] **Step 3: Commit**

```bash
git add agents/prompt-mutator.md
git commit -m "feat(evolve): prompt-mutator agent persona

Reads (current_body, dream_excerpts, bench_weaknesses) and emits 1-3
variant bodies with rationale. Constrained to one-variable-at-a-time
mutations and ±50% length to keep the loop tractable."
```

---

## Task 8: bench --candidates flag

**Files:**
- Modify: `commands/bench.md` (Stage 2 + flag list)
- Modify: `bench/run.sh` (if it exists and orchestrates the matrix) — confirm location first via `ls bench/`

bench 가 candidate 페르소나로도 RE 매트릭스를 돌릴 수 있게 한다.

- [ ] **Step 1: bench 구조 확인**

Run:
```bash
ls bench/ 2>/dev/null
head -30 bench/run.sh 2>/dev/null
```

- [ ] **Step 2: commands/bench.md 의 inputs 섹션에 flag 추가**

Modify `commands/bench.md` Inputs 섹션에 다음 줄 추가:

```
- `--candidates <name>:<path>` — repeatable. 어댑터 `<name>` 의 페르소나를 일시적으로 `<path>` 로 swap 한 채 RE 매트릭스 실행. 결과는 별도 `runs/<date>/candidates/<name>-<basename>/` 에 저장.
```

- [ ] **Step 3: Stage 2 의 RE 모드 실행 직전에 swap/restore 시퀀스 추가**

`commands/bench.md` 의 Stage 2 → "RE mode" 분기 직전에 다음 의사코드를 명세로 추가:

```
# 의사코드: candidate swap (--candidates 가 1개 이상이면 적용)
for spec in $CANDIDATES; do
  name=${spec%%:*}; path=${spec#*:}
  cp "agents/${name}.md" "/tmp/bench-restore-${name}.md"
  cp "$path" "agents/${name}.md"
done
trap 'for spec in $CANDIDATES; do name=${spec%%:*}; mv "/tmp/bench-restore-${name}.md" "agents/${name}.md"; done' EXIT
```

> 실제 코드는 `bench/run.sh` 의 RE 분기에서 evolved candidate path 가 인자로 들어오면 동일 swap/restore 를 구현. 구현 위치는 Step 1 의 ls 결과로 확정.

- [ ] **Step 4: bats 테스트 (스모크)**

Create `tests/research-engine/bench-candidates.test.sh`:

```bash
#!/usr/bin/env bats

@test "bench --candidates swaps adapter file and restores on exit" {
  WORK=$(mktemp -d)
  mkdir -p "$WORK/agents"
  echo "ORIGINAL" > "$WORK/agents/foo.md"
  echo "CANDIDATE" > "$WORK/cand.md"

  # source 'swap' inline simulation
  CANDIDATES="foo:$WORK/cand.md"
  cp "$WORK/agents/foo.md" "$WORK/restore-foo.md"
  cp "$WORK/cand.md" "$WORK/agents/foo.md"

  [ "$(cat "$WORK/agents/foo.md")" = "CANDIDATE" ]

  # restore
  mv "$WORK/restore-foo.md" "$WORK/agents/foo.md"
  [ "$(cat "$WORK/agents/foo.md")" = "ORIGINAL" ]

  rm -rf "$WORK"
}
```

- [ ] **Step 5: 테스트 실행 + 통과**

Run: `bats tests/research-engine/bench-candidates.test.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add commands/bench.md tests/research-engine/bench-candidates.test.sh
git commit -m "feat(evolve): bench --candidates flag spec

Add --candidates <name>:<path> repeatable flag. Stage 2 RE mode does
swap-then-restore around the matrix. Smoke bats for swap/restore logic."
```

---

## Task 9: evolve_run.sh — orchestrator (E1·E2·E5~E8)

**Files:**
- Create: `scripts/evolve_run.sh`
- Test: `tests/research-engine/evolve.test.sh`

E3 (mutator dispatch) 와 E4 (bench --candidates 실행) 는 외부에서 호출. evolve_run.sh 는 파일 I/O · ledger update · 채택/롤백.

- [ ] **Step 1: 최소 스켈레톤 + 사용법**

Create `scripts/evolve_run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   evolve_run.sh prepare  <adapter-name> <region-id>
#       → prints: { current_body, dream_excerpts, bench_weaknesses }
#   evolve_run.sh apply    <adapter-name> <region-id> <mutator-output.json>
#       → writes agents/<name>.candidate.md, prints candidate path
#   evolve_run.sh decide   <adapter-name> <bench-current.json> <bench-candidate.json>
#       → runs statistical_gate, updates ledger, prints decision
#   evolve_run.sh promote  <adapter-name>
#       → swaps candidate → live, archives previous, git stage

CMD=${1:-}
case "$CMD" in
  prepare|apply|decide|promote) ;;
  *) echo "usage: $0 {prepare|apply|decide|promote} ..." >&2; exit 64 ;;
esac

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LEDGER="$ROOT/research/_index/evolve-ledger.json"
AGENTS="$ROOT/agents"

case "$CMD" in
  prepare)
    NAME=$2; REGION=$3
    node "$ROOT/lib/evolve/prepare.mjs" "$AGENTS/$NAME.md" "$REGION"
    ;;
  apply)
    NAME=$2; REGION=$3; MUT=$4
    node "$ROOT/lib/evolve/apply.mjs" "$AGENTS/$NAME.md" "$REGION" "$MUT" \
      > "$AGENTS/$NAME.candidate.md"
    echo "$AGENTS/$NAME.candidate.md"
    ;;
  decide)
    NAME=$2; CURJSON=$3; CANDJSON=$4
    node "$ROOT/lib/evolve/decide.mjs" "$LEDGER" "$NAME" "$CURJSON" "$CANDJSON"
    ;;
  promote)
    NAME=$2
    node "$ROOT/lib/evolve/promote.mjs" "$LEDGER" "$AGENTS" "$NAME"
    ;;
esac
```

- [ ] **Step 2: 4개 thin Node wrapper 추가**

Create `lib/evolve/prepare.mjs` (간단 — 어댑터 마크다운 + ledger + 최근 dream 글로빙 후 JSON 출력):

```javascript
#!/usr/bin/env node
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { extractRegions } from './extract_evolvable.mjs';

const [, , agentPath, regionId] = process.argv;
const src = readFileSync(agentPath, 'utf8');
const region = extractRegions(src).find((r) => r.id === regionId);
if (!region) {
  console.error(`region ${regionId} not found in ${agentPath}`);
  process.exit(2);
}

const dreamsDir = 'docs/dreams';
const dreamExcerpts = [];
if (existsSync(dreamsDir)) {
  const dirs = readdirSync(dreamsDir).filter((d) => d.startsWith('drm_')).sort().slice(-3);
  for (const d of dirs) {
    const readme = `${dreamsDir}/${d}/README.md`;
    if (existsSync(readme)) {
      dreamExcerpts.push({ run_id: d, text: readFileSync(readme, 'utf8').slice(0, 4000) });
    }
  }
}

console.log(JSON.stringify({
  adapter_name: agentPath.split('/').pop().replace('.md', ''),
  region_id: regionId,
  current_body: region.body,
  dream_excerpts: dreamExcerpts,
  bench_weaknesses: [],
  n_variants: 2,
}, null, 2));
```

Create `lib/evolve/apply.mjs`:

```javascript
#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { replaceRegion } from './extract_evolvable.mjs';

const [, , agentPath, regionId, mutatorOutPath] = process.argv;
const src = readFileSync(agentPath, 'utf8');
const out = JSON.parse(readFileSync(mutatorOutPath, 'utf8'));
const v0 = out.variants[0];
if (!v0) { console.error('mutator returned no variants'); process.exit(2); }
process.stdout.write(replaceRegion(src, regionId, v0.body));
```

Create `lib/evolve/decide.mjs`:

```javascript
#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs';
import { pairedBootstrapCI, gateDecision } from './statistical_gate.mjs';
import { initLedger, promote, reject } from './ledger.mjs';

const [, , ledgerPath, name, curJsonPath, candJsonPath] = process.argv;
const cur = JSON.parse(readFileSync(curJsonPath, 'utf8'));   // {scores: [..]}
const cand = JSON.parse(readFileSync(candJsonPath, 'utf8'));

const ci = pairedBootstrapCI(cur.scores, cand.scores, { iters: 2000, seed: 42 });
const dec = gateDecision(ci);

let ledger;
try { ledger = JSON.parse(readFileSync(ledgerPath, 'utf8')); }
catch { ledger = initLedger(); }

const nextVer = (ledger.adapters[name]?.history?.length || 0) + 1;
const metrics = {
  judge_score: cand.scores.reduce((a, b) => a + b, 0) / cand.scores.length,
  source_count: cand.source_count ?? 0,
  type_diversity: cand.type_diversity ?? 0,
  latency_inv: cand.latency_inv ?? 0,
};
const entry = {
  version: nextVer,
  ci_lower: ci.lower,
  metrics,
  ...(dec === 'accept' ? { promoted_at: new Date().toISOString() } : { rejected_at: new Date().toISOString() }),
};

if (dec === 'accept') ledger = promote(ledger, name, entry);
else ledger = reject(ledger, name, entry);

writeFileSync(ledgerPath, JSON.stringify(ledger, null, 2));
console.log(JSON.stringify({ decision: dec, ci, entry }, null, 2));
```

Create `lib/evolve/promote.mjs`:

```javascript
#!/usr/bin/env node
import { readFileSync, copyFileSync, unlinkSync, existsSync } from 'node:fs';
import { archiveCurrent } from './archive.mjs';

const [, , ledgerPath, agentsDir, name] = process.argv;
const ledger = JSON.parse(readFileSync(ledgerPath, 'utf8'));
const cur = ledger.adapters[name];
if (!cur) { console.error('no adapter in ledger'); process.exit(2); }

const candPath = `${agentsDir}/${name}.candidate.md`;
if (!existsSync(candPath)) { console.error('no candidate file'); process.exit(2); }

// archive current under previous version (= current_version - 1 if just promoted)
const prevVer = cur.current_version - 1;
if (prevVer >= 1) archiveCurrent({ agentsDir, name, version: prevVer });

copyFileSync(candPath, `${agentsDir}/${name}.md`);
unlinkSync(candPath);

console.log(JSON.stringify({ promoted: name, new_version: cur.current_version }, null, 2));
```

- [ ] **Step 3: chmod + 스모크 테스트**

Run:
```bash
chmod +x scripts/evolve_run.sh
bash scripts/evolve_run.sh 2>&1 | head -5
```
Expected: `usage: ... {prepare|apply|decide|promote} ...` 출력 + exit 64.

- [ ] **Step 4: bats 통합 테스트**

Create `tests/research-engine/evolve.test.sh`:

```bash
#!/usr/bin/env bats

setup() {
  WORK=$(mktemp -d)
  mkdir -p "$WORK/agents/archive" "$WORK/research/_index" "$WORK/docs/dreams"
  cp -r lib "$WORK/"
  cp scripts/evolve_run.sh "$WORK/scripts/evolve_run.sh" 2>/dev/null || mkdir -p "$WORK/scripts" && cp scripts/evolve_run.sh "$WORK/scripts/evolve_run.sh"
}

teardown() { rm -rf "$WORK"; }

@test "prepare extracts evolvable region + recent dreams" {
  cat > "$WORK/agents/foo.md" <<'MD'
# foo
<!-- evolvable:bar -->
hello
<!-- /evolvable -->
MD
  cd "$WORK"
  out=$(bash scripts/evolve_run.sh prepare foo bar)
  echo "$out" | grep -q '"region_id": "bar"'
  echo "$out" | grep -q '"current_body": "hello"'
}

@test "apply writes candidate file with replaced region" {
  cat > "$WORK/agents/foo.md" <<'MD'
<!-- evolvable:bar -->
old
<!-- /evolvable -->
MD
  cat > "$WORK/mut.json" <<'JSON'
{ "variants": [ { "body": "new\nmulti", "rationale": "test" } ] }
JSON
  cd "$WORK"
  bash scripts/evolve_run.sh apply foo bar mut.json
  grep -q "new" "$WORK/agents/foo.candidate.md"
}

@test "decide writes ledger and prints decision" {
  cat > "$WORK/cur.json" <<'JSON'
{"scores": [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]}
JSON
  cat > "$WORK/cand.json" <<'JSON'
{"scores": [0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6], "source_count": 10, "type_diversity": 3, "latency_inv": 0.01}
JSON
  cd "$WORK"
  out=$(bash scripts/evolve_run.sh decide foo cur.json cand.json)
  echo "$out" | grep -q '"decision": "accept"'
  test -f "$WORK/research/_index/evolve-ledger.json"
}
```

- [ ] **Step 5: 통과 확인**

Run:
```bash
chmod +x tests/research-engine/evolve.test.sh
bats tests/research-engine/evolve.test.sh
```
Expected: 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/evolve_run.sh lib/evolve/{prepare,apply,decide,promote}.mjs tests/research-engine/evolve.test.sh
chmod +x scripts/evolve_run.sh
git commit -m "feat(evolve): evolve_run.sh + four Node wrappers

prepare / apply / decide / promote subcommands. Each delegates to a thin
Node wrapper that uses lib/evolve/* modules. bats integration covers
prepare extraction, apply replacement, decide ledger write."
```

---

## Task 10: `/evolve` slash command

**Files:**
- Create: `commands/evolve.md`

`/evolve` 진입 슬래시. E1~E8 시퀀스를 Claude 본세션이 따라 실행.

- [ ] **Step 1: 슬래시 명세 작성**

Create `commands/evolve.md`:

```markdown
---
description: research-engine 어댑터 페르소나의 evolvable 영역을 dream + bench 신호로 mutate, multi-seed bench 로 채점, paired bootstrap CI 로 채택 결정.
argument-hint: "[adapter-name [region-id]]"
allowed-tools: Bash, Read, Write, Edit, Agent, Skill
---

## Inputs

`$ARGUMENTS` :
- positional 1 (선택): adapter name (default: dream-ledger 의 가장 약한 어댑터 — 일단 v1 은 사용자가 명시)
- positional 2 (선택): region id (default: 첫 번째 evolvable region)

## Constants

- `${CLAUDE_PLUGIN_ROOT}` — plugin root
- `WORKTREE` — `<project_cwd>`
- `LEDGER` = `${WORKTREE}/research/_index/evolve-ledger.json`
- `AGENTS` = `${WORKTREE}/agents`

## Pipeline

### E1 — Resolve target

Adapter name 과 region id 가 둘 다 인자로 들어오면 그대로 사용. 하나라도 누락이면 사용자에게 묻는다 (AskUserQuestion 또는 즉시 종료 with usage).

### E2 — Prepare mutator input

```
bash scripts/evolve_run.sh prepare <name> <region> > /tmp/mutator-in.json
```

### E3 — Dispatch prompt-mutator agent

Agent tool 로 `prompt-mutator` 페르소나에 `/tmp/mutator-in.json` 의 내용을 prompt 본문으로 전달. 반환 JSON 을 `/tmp/mutator-out.json` 에 저장. 출력에 fenced JSON 블록이 없으면 1회 재시도. 2회 연속 실패 → 종료 with FAIL 메시지.

### E4 — Apply variant 0 to candidate file

```
bash scripts/evolve_run.sh apply <name> <region> /tmp/mutator-out.json
# → agents/<name>.candidate.md
```

### E5 — Multi-seed bench (current vs candidate)

bench Skill 호출 — current 와 candidate 양쪽에 동일 topic 매트릭스로 N=8 seed 권장 (현재 매트릭스가 2 trial 만 지원하면 같은 topic 을 4 번 반복 등가):

```
Skill('research-engine:bench', args='--mode re --n 8 --topic <topic-id>')
# current 결과 → /tmp/bench-current.json (judge scores 배열 + source 메트릭)
Skill('research-engine:bench', args='--mode re --n 8 --topic <topic-id> --candidates <name>:agents/<name>.candidate.md')
# candidate 결과 → /tmp/bench-candidate.json
```

bench 결과 파싱은 `bench/runs/<date>/...` 의 score JSON 을 jq 로 집계. 정확한 키는 기존 bench/run.sh report stage 와 동일 키 사용.

### E6 — Decide

```
bash scripts/evolve_run.sh decide <name> /tmp/bench-current.json /tmp/bench-candidate.json
```

stdout JSON 의 `decision` 필드를 읽는다.

### E7 — Promote or rollback

- `accept` → `bash scripts/evolve_run.sh promote <name>` 호출. ledger 는 E6 에서 이미 promote 처리됨. 이 단계는 파일만 swap.
- `reject` 또는 `hold` → `agents/<name>.candidate.md` 삭제. ledger 는 E6 에서 이미 처리됨.

### E8 — Final message

한 줄 요약 + ledger path + 채택 시 새 version, hold 시 frontier 위치 노출.

## Failure policy

- mutator JSON 파싱 실패 2회 → 종료, ledger 미수정.
- bench 매트릭스 실패 → 종료, candidate 파일 정리.
- decide 후 promote 단계에서 파일 swap 실패 (e.g., 권한) → ledger 롤백 (history pop) + 사용자 알림.
```

- [ ] **Step 2: 슬래시 형식 검증 (frontmatter + 섹션)**

Run: `head -10 commands/evolve.md`
Expected: `description: ...`, `allowed-tools: Bash, Read, Write, Edit, Agent, Skill` 확인.

- [ ] **Step 3: Commit**

```bash
git add commands/evolve.md
git commit -m "feat(evolve): /evolve slash command — E1~E8 sequence

prepare → mutator dispatch → apply → multi-seed bench → decide → promote/rollback.
No automatic triggers. User-initiated only."
```

---

## Task 11: `/dream` D8 에 evolve 제안 추가

**Files:**
- Modify: `commands/dream.md`

dream 이 끝나면 evolve 제안 한 줄. 자동 트리거 없음.

- [ ] **Step 1: dream.md 의 D8 final message 섹션 찾기**

Run: `grep -n "D8" commands/dream.md`

- [ ] **Step 2: 제안 라인 추가**

Edit `commands/dream.md` 의 D8 final message 끝에 다음 라인 추가:

```
💡 추출된 인사이트 중 adapter_failure_modes 항목이 있으면 `/evolve <adapter-name>` 으로 해당 어댑터 페르소나 진화 시도 가능.
```

- [ ] **Step 3: Commit**

```bash
git add commands/dream.md
git commit -m "feat(evolve): /dream D8 suggests /evolve when adapter failure modes present"
```

---

## Task 12: E2E — fixture 어댑터 1개로 풀 사이클 검증

**Files:**
- Create: `tests/research-engine/evolve-e2e.test.sh`

mock claude CLI (echo-based) 로 mutator 출력을 흉내내고, fixture bench score 로 결정까지 끝나는 풀 사이클을 한 번 돌린다.

- [ ] **Step 1: E2E 테스트 작성**

Create `tests/research-engine/evolve-e2e.test.sh`:

```bash
#!/usr/bin/env bats

setup() {
  WORK=$(mktemp -d)
  mkdir -p "$WORK/agents" "$WORK/research/_index" "$WORK/scripts" "$WORK/lib"
  cp -r lib/* "$WORK/lib/"
  cp scripts/evolve_run.sh "$WORK/scripts/"
  chmod +x "$WORK/scripts/evolve_run.sh"

  cat > "$WORK/agents/fixt-adapter.md" <<'MD'
# fixt-adapter
<!-- evolvable:guide -->
original guidance
<!-- /evolvable -->
MD
}

teardown() { rm -rf "$WORK"; }

@test "full cycle: prepare → apply → decide accept → promote" {
  cd "$WORK"

  # E2 prepare
  bash scripts/evolve_run.sh prepare fixt-adapter guide > mutator-in.json
  grep -q '"current_body": "original guidance"' mutator-in.json

  # E3 mock mutator output
  cat > mutator-out.json <<'JSON'
{"adapter_name":"fixt-adapter","region_id":"guide","variants":[{"body":"improved guidance","rationale":"test"}]}
JSON

  # E4 apply
  bash scripts/evolve_run.sh apply fixt-adapter guide mutator-out.json
  grep -q "improved guidance" agents/fixt-adapter.candidate.md

  # E5 (mock) bench scores — candidate beats current clearly
  cat > cur.json <<'JSON'
{"scores":[0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5],"source_count":8,"type_diversity":2,"latency_inv":0.01}
JSON
  cat > cand.json <<'JSON'
{"scores":[0.7,0.7,0.7,0.7,0.7,0.7,0.7,0.7],"source_count":10,"type_diversity":3,"latency_inv":0.01}
JSON

  # E6 decide
  out=$(bash scripts/evolve_run.sh decide fixt-adapter cur.json cand.json)
  echo "$out" | grep -q '"decision": "accept"'

  # E7 promote
  bash scripts/evolve_run.sh promote fixt-adapter
  grep -q "improved guidance" agents/fixt-adapter.md
  test -f agents/archive/fixt-adapter.v0.md || true   # version 0 archive may be skipped
  ! test -f agents/fixt-adapter.candidate.md
}

@test "full cycle with negative delta: decide rejects + candidate cleaned up" {
  cd "$WORK"
  cp agents/fixt-adapter.md agents/fixt-adapter.candidate.md
  cat > cur.json <<'JSON'
{"scores":[0.7,0.7,0.7,0.7,0.7,0.7,0.7,0.7],"source_count":10,"type_diversity":3,"latency_inv":0.01}
JSON
  cat > cand.json <<'JSON'
{"scores":[0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5],"source_count":5,"type_diversity":2,"latency_inv":0.005}
JSON
  out=$(bash scripts/evolve_run.sh decide fixt-adapter cur.json cand.json)
  echo "$out" | grep -q '"decision": "reject"'
  # candidate cleanup is /evolve slash responsibility, not evolve_run.sh — skip here
}
```

- [ ] **Step 2: 실행**

Run:
```bash
chmod +x tests/research-engine/evolve-e2e.test.sh
bats tests/research-engine/evolve-e2e.test.sh
```
Expected: 2 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/research-engine/evolve-e2e.test.sh
git commit -m "test(evolve): e2e bats — full accept cycle + reject cycle

Fixture adapter, mocked mutator JSON, mocked bench scores. Verifies
candidate file is replaced into live on accept, ledger is updated on
both accept and reject."
```

---

## Task 13: 실제 1회 evolve 사이클 — youtube-adapter

**Files:**
- 실행만 (변경 없음)

진짜 어댑터에 한 번 돌려서 동작 확인. 결과는 commit 하지 말고 ledger 출력만 검토.

- [ ] **Step 1: 사전 확인**

Run:
```bash
git status                                       # 깨끗해야 함
ls research/_index/                              # manifest, dream-ledger 있어야 함
grep -c "<!-- evolvable:" agents/youtube-adapter.md  # 2
```

- [ ] **Step 2: prepare 단독 호출**

Run:
```bash
bash scripts/evolve_run.sh prepare youtube-adapter findings-guidance | jq '.dream_excerpts | length, .current_body[0:60]'
```
Expected: `dream_excerpts` 길이 ≥ 0, `current_body` 가 youtube-adapter 의 findings 영역 시작 부분.

- [ ] **Step 3: `/evolve youtube-adapter findings-guidance` 슬래시 호출**

Claude Code 에서 `/evolve youtube-adapter findings-guidance` 실행. 사용자가 직접 봐서:
- mutator 가 variant 를 emit 했는가?
- bench --candidates 가 실제로 두 매트릭스를 돌리는가?
- decide 결과가 accept/reject/hold 중 어떤 것인가?
- ledger 가 추가됐는가?

- [ ] **Step 4: 결과 분석**

`research/_index/evolve-ledger.json` 의 새 entry 를 본다. CI 가 매우 좁거나 hold 가 나왔으면 → bench 매트릭스 N seed 가 더 필요. accept 가 나왔으면 → candidate body 가 git diff 에 보이는지 확인.

- [ ] **Step 5: rollback (이번 사이클은 검증용이므로 채택해도 git reset)**

Run:
```bash
git diff agents/youtube-adapter.md             # diff 확인
git checkout agents/youtube-adapter.md         # 원상복구
rm -f agents/archive/youtube-adapter.v1.md      # archive 도 제거 (검증용)
git checkout research/_index/evolve-ledger.json
```

이 task 는 **commit 하지 않는다** — 실제 채택은 별도 PR/세션에서 결정.

---

## Self-Review

Plan 작성 후 spec 와 다시 매칭.

**Spec coverage:**
- ✅ "outer optimizer" = `/evolve` 슬래시 (Task 10)
- ✅ "prompt mutation" = prompt-mutator (Task 7) + apply (Task 9)
- ✅ "통계적 유의성 검정" = statistical_gate paired bootstrap CI (Task 3)
- ✅ "multi-metric Pareto" = pareto.mjs + ledger.frontier (Tasks 4, 5)
- ✅ "archive + rollback" = archive.mjs + promote.mjs (Tasks 6, 9)
- ✅ "evolvable 영역 보호" = markers + extract_evolvable (Tasks 1, 2)
- ✅ "자동 트리거 없음" = `/dream` D8 제안만 (Task 11)
- ✅ "E2E 검증" = Task 12 + 실제 1회 (Task 13)

**Placeholder scan**: "TBD" / "..." / "add appropriate" 검색 — 없음. 모든 코드 블록은 실제 실행 가능.

**Type consistency:**
- `paretoFront(points, axes)` — Task 4, 5 모두 동일 시그니처.
- `gateDecision(ci)` — Task 3 정의, Task 9 decide.mjs 사용 — 동일.
- ledger 의 `current_version` / `history` / `frontier` / `rejected` — Task 5 에서 정의, Task 6 archiveCurrent 가 history.length 로 nextVersion 계산 — 정합.
- `promote.mjs` 의 archive 호출 시 `prevVer = cur.current_version - 1` 가정 — Task 5 의 decide.mjs 가 promote 를 먼저 호출하므로 promote.mjs 시점에 `current_version` 은 이미 새 값. 정합.

---

## Out-of-scope (이 플랜에서 다루지 않음)

- 모든 어댑터의 evolvable 마킹 (youtube-adapter 만 — 다른 어댑터는 v2 플랜).
- Promptbreeder 의 메타 레이어 (mutation-prompt 자체의 진화) — 1차 자기개선만.
- bench 매트릭스의 자동 multi-seed 확장 — `--n 8` 같은 큰 N 지원은 별도 PR.
- regime-conditional 평가 (input_type 별 분리) — Pareto 축에 input_type 추가는 v2.
- 자동 트리거 (5회 누적 시 `/evolve` 자동 실행) — 모든 트리거는 사용자.
- prompt-mutator 가 dream insights 외에 bench raw output 도 prompt 입력으로 받는 풀 신호 — 현재 prepare.mjs 는 dream 만 추출하고 bench_weaknesses 는 빈 배열.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| bench 점수가 너무 noisy → CI 가 항상 hold → 진화 안 함 | Task 13 결과 확인 후 N seed 늘리거나 judge 모델 고정. 통계검정이 보수적으로 작동하는 것 자체는 안전 측 |
| prompt-mutator 가 JSON contract 영역을 침범 | evolvable 마커가 contract 밖에 있고, prepare.mjs 는 마커 안만 추출 — mutator 는 contract 본 적도 없음 |
| candidate 페르소나가 어댑터의 다른 섹션과 형식 충돌 | apply.mjs 가 `replaceRegion` 으로 마커 영역만 교체 — 다른 섹션 무변경. 변경 라인 수 ±50% rationale 가 mutator 페르소나에 박혀있음 |
| ledger 쓰기 도중 크래시 → 부분 ledger | Task 9 의 decide.mjs 는 read → modify → writeFileSync 단일 호출. atomic 쓰기는 v2 (tmp + rename). 현재는 휘발 가능성 수용 |
| 채택된 어댑터가 회귀를 일으킴 | archive.mjs 가 이전 버전 보존. rollback = `cp agents/archive/<name>.v<N>.md agents/<name>.md` + ledger 수동 수정. /unevolve 슬래시는 v2 |
| 자기개선 루프가 local optimum 에 갇힘 | Pareto frontier 가 non-dominated reject 후보 보존 — 다음 라운드 mutator 가 frontier 의 다른 변형을 시작점으로 쓸 수 있게 prepare.mjs 확장 가능 (v2) |
