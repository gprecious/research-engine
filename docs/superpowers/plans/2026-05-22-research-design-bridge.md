# `/research-design` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/research-design <slug>` 한 번으로 — claude.ai/design 자동화로 인터랙티브 프로토타입을 받고, Claude Code 와 Codex 가 병렬로 Next.js 앱을 구현 후 비판적 cross-review 로 합쳐, hetzner-master LXC 컨테이너에 배포한다. 3중 게이트 (Playwright e2e + 4축 LLM judge) 통과해야 성공.

**Architecture:** 5-phase pipeline — (1) RED 테스트 4종 commit, (2) 인증·collect (cloak-browser → Tailscale m4 fallback), (3) handoff parser + scaffold + 워커 agent 프롬프트, (4) herdr 4-pane 오케스트레이션 + 4축 judge, (5) LXC 배포 + top-level orchestrator + slash command. 각 phase 별로 working software 가 나온다.

**Tech Stack:** Node 22 (.mjs), bash, Playwright (npm), cloak-browser (npm, lazy install), herdr (이미 PATH), `claude -p` / `codex exec` (헤드리스 LLM 워커), Next.js 14 (앱 scaffold), Caddy + systemd (LXC), Tailscale (m4 attach + LXC 등록), hetzner-proxmox-deploy skill, bats (shell tests), Vitest (mjs unit tests).

**Spec:** `docs/superpowers/specs/2026-05-22-research-design-bridge.md`

**시드 슬러그:** `2026-05-22-ai-image-vectorization-service`

---

## File Structure

### Create

| Path | Responsibility |
|---|---|
| `commands/research-design.md` | Slash 명령 entrypoint — 인자 파싱 → pipeline 호출 |
| `agents/design-builder.md` | Claude/Codex worker 공통 build 프롬프트 (handoff → Next.js 앱) |
| `agents/design-critic.md` | 상대 PR 비판적 review 프롬프트 (accept/reject notes 생성) |
| `agents/design-merger.md` | 두 결과 + review 를 통합본으로 합치는 프롬프트 |
| `scripts/research_design_pipeline.sh` | Top-level orchestrator (모든 단계 호출, log.jsonl, 게이트 평가) |
| `scripts/cloak_login.mjs` | cloak-browser 자동 로그인 시도 (env 자격증명, captcha 시 fail-fast) |
| `scripts/manual_login.mjs` | Tailscale m4 Chrome 으로 사용자 1회 로그인 (CDP attach → storageState 추출) |
| `scripts/design_collect.mjs` | storageState 캐시 검사 → 로그인 chain → claude.ai/design 자동화 → handoff bundle 다운로드 |
| `scripts/herdr_orchestrate.sh` | 4 herdr pane 생성 + claude/codex 헤드리스 워커 spawn + 결과 수집 |
| `scripts/judge_app.mjs` | 4축 LLM judge — screenshot + scenarios.json 입력, 점수 JSON 출력 |
| `scripts/lxc_deploy.sh` | hetzner-proxmox-deploy 호출 wrapper — LXC + Caddy + systemd + Tailscale |
| `lib/design_handoff_parser.mjs` | handoff bundle 파싱 (컴포넌트/asset 추출, normalized JSON 반환) |
| `lib/app_scaffold.mjs` | Next.js base 스캐폴드 생성 + handoff 콘텐츠 주입 |
| `lib/research_design_env.mjs` | `.env.research-design` 로더 (dotenv 없는 의도적 경량 구현) |
| `tests/research-design/schemas/scenarios.schema.json` | scenarios.json JSON Schema |
| `tests/research-design/e2e/runner.ts` | scenarios.json → Playwright test 변환 runner |
| `tests/research-design/e2e/2026-05-22-ai-image-vectorization-service.spec.ts` | 시드 슬러그 e2e |
| `tests/research-design/fixtures/sample.png` | 업로드 시나리오용 미니 PNG (40×40) |
| `tests/research-design/fixtures/handoff-stub/` | 파서 테스트용 mock handoff bundle |
| `tests/research-design/judge_fixture.json` | judge 모의 입력/기대 출력 구조 |
| `tests/research-design/pipeline.test.sh` | bats — pipeline mock 모드 통합 |
| `tests/research-design/lib/design_handoff_parser.test.mjs` | Vitest — 파서 unit |
| `tests/research-design/lib/app_scaffold.test.mjs` | Vitest — 스캐폴드 unit |
| `tests/research-design/lib/judge_app.test.mjs` | Vitest — judge 인터페이스 |
| `research/2026-05-22-ai-image-vectorization-service/design/scenarios.json` | 시드 e2e 시나리오 (사람 작성, 개발 전 commit) |
| `.env.research-design.example` | 환경변수 템플릿 |
| `package.json` | npm scripts + devDependencies (현재 plain shell-only repo 라 신규 도입) |

### Modify

| Path | Change |
|---|---|
| `README.md` | `/research-design` 사용법 + 의존성 (Node 22, pnpm, playwright) 섹션 추가 |
| `CHANGELOG.md` | 0.11.0 entry — `/research-design` 추가 |
| `.gitignore` | `.env.research-design`, `~/.config/research-engine/claude-design/*`, `research/*/design/runs/`, `node_modules/`, `tests/research-design/fixtures/handoff-stub/.gitkeep` 추가 |
| `DEVELOPMENT.md` | Vitest + bats 실행법 추가 |

### Do not touch

`commands/research.md`, `commands/research-followup.md`, `commands/research-visualize.md`, `agents/*-adapter.md`, `agents/visualizer-*.md`, `lib/adapter_contract.md`, `lib/report_sections.md`, `lib/chart_spec_contract.md`, 기존 `scripts/*` 일체.

---

## Phase 1 — RED 게이트 테스트 commit (개발 시작 전)

사용자 요구사항: "정상작동 기준은 개발 시작 전 테스트 시나리오와 코드 작성하여 만든다." 따라서 Phase 1 의 결과물은 **RED 상태의 테스트 4종 + 시드 시나리오 JSON** 이고 commit 한다.

---

### Task 1: scenarios.json schema + 시드 시나리오

**Files:**
- Create: `tests/research-design/schemas/scenarios.schema.json`
- Create: `research/2026-05-22-ai-image-vectorization-service/design/scenarios.json`
- Create: `package.json` (최소 — vitest, ajv, playwright devDependencies)
- Create: `tests/research-design/schemas/validate-seed.test.mjs`

- [ ] **Step 1: package.json 작성**

```json
{
  "name": "research-engine",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "test:unit": "vitest run tests/research-design/lib tests/research-design/schemas",
    "test:e2e": "playwright test --config tests/research-design/e2e/playwright.config.ts",
    "test:bats": "bats tests/research-design/pipeline.test.sh"
  },
  "devDependencies": {
    "ajv": "^8.17.1",
    "ajv-formats": "^3.0.1",
    "vitest": "^1.6.0",
    "@playwright/test": "^1.45.0"
  }
}
```

- [ ] **Step 2: pnpm 설치 + lockfile 생성**

```bash
corepack enable
pnpm install
git add package.json pnpm-lock.yaml
```

- [ ] **Step 3: scenarios.schema.json 작성**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://gprecious/research-engine/schemas/scenarios.json",
  "title": "research-design e2e scenarios",
  "type": "object",
  "required": ["slug", "baseUrl", "scenarios"],
  "properties": {
    "slug": { "type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$" },
    "baseUrl": {
      "type": "object",
      "required": ["local"],
      "properties": {
        "local": { "type": "string", "format": "uri" },
        "prod": { "type": "string", "format": "uri" }
      }
    },
    "scenarios": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["name", "steps"],
        "properties": {
          "name": { "type": "string", "pattern": "^[a-z0-9-]+$" },
          "steps": {
            "type": "array",
            "minItems": 1,
            "items": {
              "type": "object",
              "oneOf": [
                { "required": ["goto"], "properties": { "goto": { "type": "string" } } },
                { "required": ["click"], "properties": { "click": { "type": "string" } } },
                { "required": ["setInputFiles"], "properties": { "setInputFiles": { "type": "array", "minItems": 2, "items": { "type": "string" } } } },
                { "required": ["waitForSelector"], "properties": { "waitForSelector": { "type": "string" }, "timeout": { "type": "integer" } } },
                { "required": ["expect"], "properties": { "expect": { "type": "object" } } },
                { "required": ["fetch"], "properties": { "fetch": { "type": "string" }, "expectStatus": { "type": "integer" } } },
                { "required": ["expectNoConsoleError"], "properties": { "expectNoConsoleError": { "type": "boolean" } } },
                { "required": ["expectNoNetworkFailure"], "properties": { "expectNoNetworkFailure": { "type": "array", "items": { "type": "string" } } } }
              ]
            }
          }
        }
      }
    }
  }
}
```

- [ ] **Step 4: 시드 scenarios.json 작성**

`research/2026-05-22-ai-image-vectorization-service/design/scenarios.json`:

```json
{
  "$schema": "../../../tests/research-design/schemas/scenarios.schema.json",
  "slug": "2026-05-22-ai-image-vectorization-service",
  "baseUrl": { "local": "http://localhost:3000" },
  "scenarios": [
    {
      "name": "landing-hero-cta",
      "steps": [
        { "goto": "/" },
        { "expect": { "selector": "h1", "containsText": "vectoriz" } },
        { "click": "[data-testid=cta-try]" },
        { "expect": { "url": "/upload" } }
      ]
    },
    {
      "name": "upload-and-preview",
      "steps": [
        { "goto": "/upload" },
        { "setInputFiles": ["input[type=file]", "tests/research-design/fixtures/sample.png"] },
        { "click": "[data-testid=convert]" },
        { "waitForSelector": "[data-testid=svg-preview] svg", "timeout": 15000 },
        { "expectNoConsoleError": true }
      ]
    },
    {
      "name": "health-and-no-runtime-error",
      "steps": [
        { "fetch": "/health", "expectStatus": 200 },
        { "goto": "/" },
        { "expectNoConsoleError": true },
        { "expectNoNetworkFailure": ["/_next/", "/api/"] }
      ]
    }
  ]
}
```

- [ ] **Step 5: schema validation test 작성**

`tests/research-design/schemas/validate-seed.test.mjs`:

```javascript
import { test, expect } from 'vitest';
import Ajv from 'ajv';
import addFormats from 'ajv-formats';
import { readFileSync } from 'node:fs';

const schema = JSON.parse(readFileSync('tests/research-design/schemas/scenarios.schema.json', 'utf8'));
const seed = JSON.parse(readFileSync('research/2026-05-22-ai-image-vectorization-service/design/scenarios.json', 'utf8'));

const ajv = new Ajv({ strict: false });
addFormats(ajv);
const validate = ajv.compile(schema);

test('시드 scenarios.json 이 schema 통과', () => {
  const ok = validate(seed);
  expect(ok, JSON.stringify(validate.errors)).toBe(true);
});

test('시드 슬러그가 디렉토리 슬러그와 일치', () => {
  expect(seed.slug).toBe('2026-05-22-ai-image-vectorization-service');
});
```

- [ ] **Step 6: 테스트 실행 — PASS 확인 (이건 input contract test 이므로 GREEN 으로 시작)**

```bash
pnpm test:unit -- tests/research-design/schemas
```

Expected: 2 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add tests/research-design/schemas/ \
        research/2026-05-22-ai-image-vectorization-service/design/scenarios.json \
        package.json pnpm-lock.yaml
git commit -m "test(research-design): scenarios schema + seed scenarios for ai-image-vectorization-service

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Playwright e2e runner + 시드 spec (RED)

**Files:**
- Create: `tests/research-design/e2e/playwright.config.ts`
- Create: `tests/research-design/e2e/runner.ts`
- Create: `tests/research-design/e2e/2026-05-22-ai-image-vectorization-service.spec.ts`
- Create: `tests/research-design/fixtures/sample.png`

- [ ] **Step 1: playwright 설치**

```bash
pnpm exec playwright install chromium --with-deps
```

- [ ] **Step 2: playwright.config.ts 작성**

```typescript
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  fullyParallel: false,
  retries: 0,
  reporter: [['list'], ['json', { outputFile: 'test-results/e2e.json' }]],
  use: {
    baseURL: process.env.E2E_BASE_URL || 'http://localhost:3000',
    headless: true,
    trace: 'retain-on-failure',
    video: 'retain-on-failure'
  }
});
```

- [ ] **Step 3: runner.ts 작성 — scenarios.json 을 playwright test 로 expand**

```typescript
import { test, expect, type Page, type ConsoleMessage } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

type Step =
  | { goto: string }
  | { click: string }
  | { setInputFiles: [string, string] }
  | { waitForSelector: string; timeout?: number }
  | { expect: { selector?: string; containsText?: string; url?: string } }
  | { fetch: string; expectStatus: number }
  | { expectNoConsoleError: boolean }
  | { expectNoNetworkFailure: string[] };

type Scenario = { name: string; steps: Step[] };
type ScenarioFile = { slug: string; baseUrl: { local: string; prod?: string }; scenarios: Scenario[] };

export function runScenarios(scenarioFilePath: string) {
  const file: ScenarioFile = JSON.parse(readFileSync(scenarioFilePath, 'utf8'));

  test.describe(`scenarios: ${file.slug}`, () => {
    for (const scenario of file.scenarios) {
      test(scenario.name, async ({ page, request, baseURL }) => {
        const consoleErrors: string[] = [];
        const networkFailures: string[] = [];

        page.on('console', (msg: ConsoleMessage) => {
          if (msg.type() === 'error') consoleErrors.push(msg.text());
        });
        page.on('response', (resp) => {
          if (resp.status() >= 400) networkFailures.push(`${resp.status()} ${resp.url()}`);
        });

        for (const step of scenario.steps) {
          await runStep(page, request, baseURL!, step, consoleErrors, networkFailures);
        }
      });
    }
  });
}

async function runStep(
  page: Page,
  request: import('@playwright/test').APIRequestContext,
  baseURL: string,
  step: Step,
  consoleErrors: string[],
  networkFailures: string[]
): Promise<void> {
  if ('goto' in step) {
    await page.goto(step.goto);
  } else if ('click' in step) {
    await page.click(step.click);
  } else if ('setInputFiles' in step) {
    const [selector, path] = step.setInputFiles;
    await page.setInputFiles(selector, resolve(path));
  } else if ('waitForSelector' in step) {
    await page.waitForSelector(step.waitForSelector, { timeout: step.timeout ?? 5000 });
  } else if ('expect' in step) {
    const e = step.expect;
    if (e.selector && e.containsText) {
      await expect(page.locator(e.selector)).toContainText(e.containsText, { ignoreCase: true });
    }
    if (e.url) {
      await expect(page).toHaveURL(new RegExp(e.url.replace(/\//g, '\\/')));
    }
  } else if ('fetch' in step) {
    const resp = await request.get(new URL(step.fetch, baseURL).toString());
    expect(resp.status()).toBe(step.expectStatus);
  } else if ('expectNoConsoleError' in step) {
    expect(consoleErrors, `console errors: ${consoleErrors.join('\n')}`).toEqual([]);
  } else if ('expectNoNetworkFailure' in step) {
    const matched = networkFailures.filter((f) => step.expectNoNetworkFailure.some((p) => f.includes(p)));
    expect(matched, `network failures: ${matched.join('\n')}`).toEqual([]);
  }
}
```

- [ ] **Step 4: 시드 spec 작성 — runner 를 호출만 함**

`tests/research-design/e2e/2026-05-22-ai-image-vectorization-service.spec.ts`:

```typescript
import { runScenarios } from './runner';

runScenarios('research/2026-05-22-ai-image-vectorization-service/design/scenarios.json');
```

- [ ] **Step 5: 40×40 sample.png 생성 (fixture)**

```bash
python3 - <<'PY'
from PIL import Image
img = Image.new('RGB', (40, 40), color=(180, 220, 255))
for x in range(40):
    for y in range(40):
        if (x+y) % 8 < 2:
            img.putpixel((x,y), (40, 80, 120))
img.save('tests/research-design/fixtures/sample.png')
PY
```

(PIL 미설치 시 `pip install Pillow`)

- [ ] **Step 6: e2e 실행 — RED 확인**

```bash
pnpm test:e2e
```

Expected: 3 tests FAIL with `net::ERR_CONNECTION_REFUSED` 또는 `http://localhost:3000` 접속 불가. **이게 의도된 RED.**

- [ ] **Step 7: Commit (RED 보존)**

```bash
git add tests/research-design/e2e/ tests/research-design/fixtures/sample.png
git commit -m "test(research-design): RED e2e for seed slug — runner + scenarios spec

Tests will FAIL until Next.js app is built and running on localhost:3000.
This is intentional — TDD red-first.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: handoff parser 인터페이스 + fixture + RED 테스트

**Files:**
- Create: `lib/design_handoff_parser.mjs` (skeleton only, throws Not Implemented)
- Create: `tests/research-design/fixtures/handoff-stub/index.html`
- Create: `tests/research-design/fixtures/handoff-stub/styles.css`
- Create: `tests/research-design/fixtures/handoff-stub/handoff.meta.json`
- Create: `tests/research-design/lib/design_handoff_parser.test.mjs`

- [ ] **Step 1: handoff-stub fixture 작성**

`tests/research-design/fixtures/handoff-stub/index.html`:

```html
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Vectorize</title><link rel="stylesheet" href="styles.css"></head>
<body>
  <header><h1>AI Image Vectorization</h1></header>
  <main>
    <section data-component="hero">
      <p class="lead">Turn raster art into clean SVG in seconds.</p>
      <button class="cta" data-action="start">Try free</button>
    </section>
    <section data-component="upload">
      <input type="file" accept="image/*"/>
      <button class="convert">Convert</button>
      <div class="svg-preview"></div>
    </section>
  </main>
</body>
</html>
```

`tests/research-design/fixtures/handoff-stub/styles.css`:

```css
:root { --bg: #f6f8fb; --fg: #0a0a2a; --accent: #6c4cff; }
body { background: var(--bg); color: var(--fg); font-family: system-ui; margin: 0; }
header { padding: 48px 24px; text-align: center; }
.cta { background: var(--accent); color: white; padding: 12px 24px; border-radius: 8px; border: 0; }
```

`tests/research-design/fixtures/handoff-stub/handoff.meta.json`:

```json
{
  "tool": "claude.ai/design",
  "exportedAt": "2026-05-22T01:00:00Z",
  "title": "AI Image Vectorization",
  "designSystem": {
    "colors": { "bg": "#f6f8fb", "fg": "#0a0a2a", "accent": "#6c4cff" },
    "typography": { "base": "system-ui" }
  },
  "components": ["hero", "upload"]
}
```

- [ ] **Step 2: parser skeleton 작성 (RED)**

`lib/design_handoff_parser.mjs`:

```javascript
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

/**
 * @param {string} bundleDir
 * @returns {{
 *   meta: object,
 *   pages: { name: string, html: string }[],
 *   styles: { name: string, css: string }[],
 *   assets: { name: string, path: string, bytes: number }[],
 *   components: string[],
 *   designSystem: object
 * }}
 */
export function parseHandoff(bundleDir) {
  throw new Error('not implemented');
}
```

- [ ] **Step 3: RED 테스트 작성**

`tests/research-design/lib/design_handoff_parser.test.mjs`:

```javascript
import { test, expect } from 'vitest';
import { parseHandoff } from '../../../lib/design_handoff_parser.mjs';

const FIXTURE = 'tests/research-design/fixtures/handoff-stub';

test('파서가 메타를 읽는다', () => {
  const out = parseHandoff(FIXTURE);
  expect(out.meta.tool).toBe('claude.ai/design');
  expect(out.meta.title).toBe('AI Image Vectorization');
});

test('파서가 HTML 페이지를 수집한다', () => {
  const out = parseHandoff(FIXTURE);
  const names = out.pages.map((p) => p.name).sort();
  expect(names).toEqual(['index.html']);
  expect(out.pages[0].html).toContain('data-component="hero"');
});

test('파서가 CSS 를 수집한다', () => {
  const out = parseHandoff(FIXTURE);
  const names = out.styles.map((s) => s.name).sort();
  expect(names).toEqual(['styles.css']);
});

test('파서가 디자인 시스템과 컴포넌트 목록을 노출한다', () => {
  const out = parseHandoff(FIXTURE);
  expect(out.designSystem.colors.accent).toBe('#6c4cff');
  expect(out.components.sort()).toEqual(['hero', 'upload']);
});
```

- [ ] **Step 4: 테스트 실행 — RED 확인**

```bash
pnpm test:unit -- tests/research-design/lib/design_handoff_parser.test.mjs
```

Expected: 4 tests FAIL with `not implemented`.

- [ ] **Step 5: Commit (RED 보존)**

```bash
git add lib/design_handoff_parser.mjs tests/research-design/fixtures/handoff-stub/ tests/research-design/lib/design_handoff_parser.test.mjs
git commit -m "test(research-design): RED parser tests + handoff-stub fixture

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: judge_app.mjs 인터페이스 + RED 테스트

**Files:**
- Create: `scripts/judge_app.mjs` (skeleton)
- Create: `tests/research-design/judge_fixture.json`
- Create: `tests/research-design/lib/judge_app.test.mjs`

- [ ] **Step 1: judge_fixture.json 작성**

```json
{
  "inputs": {
    "appScreenshotPath": "tests/research-design/fixtures/handoff-stub/index.html",
    "designScreenshotPath": "tests/research-design/fixtures/handoff-stub/index.html",
    "scenarios": {
      "$ref": "research/2026-05-22-ai-image-vectorization-service/design/scenarios.json"
    }
  },
  "expectedOutputShape": {
    "designQuality": "number 0-100",
    "originality": "number 0-100",
    "craft": "number 0-100",
    "functionality": "number 0-100",
    "total": "number (avg, 0-100)",
    "axisNotes": "object with one note per axis"
  }
}
```

- [ ] **Step 2: judge_app.mjs skeleton 작성**

`scripts/judge_app.mjs`:

```javascript
#!/usr/bin/env node
/**
 * Usage:
 *   node scripts/judge_app.mjs \
 *     --app-screenshot path/to/app.png \
 *     --design-screenshot path/to/design.png \
 *     --scenarios path/to/scenarios.json \
 *     --out path/to/score.json
 *
 * Optionally `--mock` returns a fixed score for tests.
 */
import { writeFileSync } from 'node:fs';

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i++) {
    const k = argv[i];
    if (k.startsWith('--')) {
      const key = k.slice(2);
      const v = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
      out[key] = v;
    }
  }
  return out;
}

export async function judge({ appScreenshot, designScreenshot, scenariosPath, mock = false }) {
  if (mock) {
    return {
      designQuality: 78,
      originality: 72,
      craft: 80,
      functionality: 76,
      total: 76.5,
      axisNotes: {
        designQuality: 'mock',
        originality: 'mock',
        craft: 'mock',
        functionality: 'mock'
      }
    };
  }
  throw new Error('not implemented');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = parseArgs(process.argv);
  const result = await judge({
    appScreenshot: args['app-screenshot'],
    designScreenshot: args['design-screenshot'],
    scenariosPath: args.scenarios,
    mock: !!args.mock
  });
  if (args.out) writeFileSync(args.out, JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
}
```

- [ ] **Step 3: 테스트 작성 (RED for real path, GREEN for mock)**

`tests/research-design/lib/judge_app.test.mjs`:

```javascript
import { test, expect } from 'vitest';
import { judge } from '../../../scripts/judge_app.mjs';

test('mock 모드는 결정적 결과를 낸다', async () => {
  const result = await judge({
    appScreenshot: 'irrelevant',
    designScreenshot: 'irrelevant',
    scenariosPath: 'irrelevant',
    mock: true
  });
  expect(result.total).toBeGreaterThan(0);
  expect(result.total).toBeLessThanOrEqual(100);
  for (const axis of ['designQuality', 'originality', 'craft', 'functionality']) {
    expect(typeof result[axis]).toBe('number');
    expect(typeof result.axisNotes[axis]).toBe('string');
  }
});

test('real 모드는 구현 전까지 throw', async () => {
  await expect(
    judge({ appScreenshot: 'x', designScreenshot: 'x', scenariosPath: 'x', mock: false })
  ).rejects.toThrow(/not implemented/);
});
```

- [ ] **Step 4: 테스트 실행**

```bash
pnpm test:unit -- tests/research-design/lib/judge_app.test.mjs
```

Expected: 2 tests PASS (mock 작동 + real 모드는 의도된 throw 검증).

- [ ] **Step 5: Commit**

```bash
git add scripts/judge_app.mjs tests/research-design/judge_fixture.json tests/research-design/lib/judge_app.test.mjs
git commit -m "test(research-design): judge interface + fixture, real path RED

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: pipeline.test.sh — bats mock 모드 RED

**Files:**
- Create: `tests/research-design/pipeline.test.sh`
- Create: `tests/research-design/mock-bin/` (with stubs for `claude`, `codex`, `playwright`, `pnpm`)

- [ ] **Step 1: mock bin stubs**

`tests/research-design/mock-bin/claude`:

```bash
#!/usr/bin/env bash
echo "[mock claude] $*" >&2
echo '{"status":"ok"}'
exit 0
```

`tests/research-design/mock-bin/codex`:

```bash
#!/usr/bin/env bash
echo "[mock codex] $*" >&2
echo '{"status":"ok"}'
exit 0
```

`tests/research-design/mock-bin/playwright`:

```bash
#!/usr/bin/env bash
echo "[mock playwright] $*" >&2
exit 0
```

```bash
chmod +x tests/research-design/mock-bin/{claude,codex,playwright}
```

- [ ] **Step 2: pipeline.test.sh 작성**

```bash
#!/usr/bin/env bats

setup() {
  export PATH="$(pwd)/tests/research-design/mock-bin:$PATH"
  export RESEARCH_DESIGN_MOCK=1
  export RESEARCH_DESIGN_JUDGE_MOCK=1
}

@test "pipeline script exists and is executable" {
  [ -x scripts/research_design_pipeline.sh ]
}

@test "pipeline rejects missing slug" {
  run scripts/research_design_pipeline.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"slug required"* ]]
}

@test "pipeline rejects non-existent slug" {
  run scripts/research_design_pipeline.sh "nope-doesnt-exist"
  [ "$status" -ne 0 ]
  [[ "$output" == *"README.md"* ]]
}

@test "pipeline mock run produces design/runs/<iso>/log.jsonl for seed slug" {
  run scripts/research_design_pipeline.sh "2026-05-22-ai-image-vectorization-service"
  [ "$status" -eq 0 ]
  ls research/2026-05-22-ai-image-vectorization-service/design/runs/ | grep -q '^[0-9]'
}
```

- [ ] **Step 3: bats 실행 — RED 확인**

```bash
which bats || sudo apt-get install -y bats || brew install bats-core
pnpm test:bats
```

Expected: 4 tests FAIL — `scripts/research_design_pipeline.sh` 존재하지 않음 / 권한 없음.

- [ ] **Step 4: Commit (RED 보존)**

```bash
git add tests/research-design/pipeline.test.sh tests/research-design/mock-bin/
git commit -m "test(research-design): RED pipeline mock-mode integration

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: .gitignore 보강 + .env.research-design.example

**Files:**
- Modify: `.gitignore`
- Create: `.env.research-design.example`

- [ ] **Step 1: .gitignore 보강**

`.gitignore` 끝에 추가:

```
# research-design
.env.research-design
node_modules/
research/*/design/runs/
research/*/design/handoff/
research/*/design/app/
test-results/
playwright-report/
```

- [ ] **Step 2: .env.research-design.example 작성**

```
# Anthropic claude.ai 로그인용 (cloak-browser 자동 단계에서 사용)
CLAUDE_LOGIN_EMAIL=
CLAUDE_LOGIN_PW=

# Tailscale m4 폴백 (cloak 실패 시 수동 로그인)
M4_TAILSCALE_HOST=m4
M4_TAILSCALE_USER=taejin

# hetzner-master Proxmox lab
HETZNER_MASTER_HOST=195.201.80.242
HETZNER_MASTER_USER=root

# (옵션) judge 가 호출할 Anthropic API key — 미설정시 `claude -p` 로 fallback
ANTHROPIC_API_KEY=
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore .env.research-design.example
git commit -m "chore(research-design): .gitignore + env example for design pipeline

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 2 — 인증 & handoff collect

### Task 7: env 로더 lib

**Files:**
- Create: `lib/research_design_env.mjs`
- Create: `tests/research-design/lib/env.test.mjs`

- [ ] **Step 1: env 로더 작성**

`lib/research_design_env.mjs`:

```javascript
import { readFileSync, existsSync } from 'node:fs';

export function loadEnv(path = '.env.research-design') {
  if (!existsSync(path)) return {};
  const out = {};
  const lines = readFileSync(path, 'utf8').split(/\r?\n/);
  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq < 0) continue;
    const k = line.slice(0, eq).trim();
    const v = line.slice(eq + 1).trim().replace(/^["']|["']$/g, '');
    out[k] = v;
  }
  return out;
}

export function requireEnv(keys, env = loadEnv()) {
  const missing = keys.filter((k) => !env[k] && !process.env[k]);
  if (missing.length) throw new Error(`missing env: ${missing.join(', ')}`);
  return Object.fromEntries(keys.map((k) => [k, env[k] ?? process.env[k]]));
}
```

- [ ] **Step 2: 테스트**

`tests/research-design/lib/env.test.mjs`:

```javascript
import { test, expect } from 'vitest';
import { writeFileSync, unlinkSync } from 'node:fs';
import { loadEnv, requireEnv } from '../../../lib/research_design_env.mjs';

test('loadEnv 가 .env 형식을 읽는다', () => {
  const tmp = '.env.research-design.test';
  writeFileSync(tmp, '# comment\nA=1\nB="two"\nC=three\n\n');
  try {
    const env = loadEnv(tmp);
    expect(env).toEqual({ A: '1', B: 'two', C: 'three' });
  } finally {
    unlinkSync(tmp);
  }
});

test('requireEnv 가 누락 키를 알린다', () => {
  expect(() => requireEnv(['NEVER_SET_X'], {})).toThrow(/missing env: NEVER_SET_X/);
});
```

- [ ] **Step 3: 실행 + commit**

```bash
pnpm test:unit -- tests/research-design/lib/env.test.mjs
git add lib/research_design_env.mjs tests/research-design/lib/env.test.mjs
git commit -m "feat(research-design): minimal env loader for pipeline scripts"
```

---

### Task 8: cloak_login.mjs

**Files:**
- Create: `scripts/cloak_login.mjs`

- [ ] **Step 1: cloak-browser 가용성 헬퍼 + cloak_login.mjs 작성**

```javascript
#!/usr/bin/env node
/**
 * cloak_login.mjs
 *   - cloak-browser 로 headless 자격증명 로그인 시도
 *   - 성공 시 storageState 를 ~/.config/research-engine/claude-design/storageState.json 으로 저장
 *   - hCaptcha/Cloudflare 감지 시 즉시 exit 2 (fail-fast)
 */
import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';
import { execSync, spawnSync } from 'node:child_process';
import { loadEnv, requireEnv } from '../lib/research_design_env.mjs';

const CACHE_DIR = join(homedir(), '.config', 'research-engine', 'claude-design');
const STATE_PATH = join(CACHE_DIR, 'storageState.json');
const META_PATH = join(CACHE_DIR, 'state.meta.json');

function ensureCloakBrowser() {
  try {
    require.resolve('cloak-browser');
  } catch {
    console.error('[cloak] cloak-browser not found — installing local copy');
    spawnSync('pnpm', ['add', '-D', 'cloak-browser', 'playwright'], { stdio: 'inherit' });
  }
}

async function main() {
  ensureCloakBrowser();
  const env = loadEnv();
  const { CLAUDE_LOGIN_EMAIL, CLAUDE_LOGIN_PW } = requireEnv(['CLAUDE_LOGIN_EMAIL', 'CLAUDE_LOGIN_PW'], env);

  const { stealth } = await import('cloak-browser');
  const { chromium } = await import('playwright');

  const browser = await chromium.launch({ headless: true });
  const context = await stealth(browser).newContext();
  const page = await context.newPage();

  await page.goto('https://claude.ai/login', { waitUntil: 'domcontentloaded' });
  if (await page.locator('iframe[src*="hcaptcha"], #challenge-stage').count()) {
    console.error('[cloak] captcha detected — fail-fast');
    await browser.close();
    process.exit(2);
  }

  await page.fill('input[type=email]', CLAUDE_LOGIN_EMAIL);
  await page.click('button[type=submit]');
  await page.waitForLoadState('domcontentloaded');

  if (await page.locator('iframe[src*="hcaptcha"], #challenge-stage').count()) {
    console.error('[cloak] captcha detected after email — fail-fast');
    await browser.close();
    process.exit(2);
  }

  await page.fill('input[type=password]', CLAUDE_LOGIN_PW);
  await page.click('button[type=submit]');

  await page.goto('https://claude.ai/design');
  const ok = await page
    .locator('[data-testid=user-menu], header img[alt*="avatar"], nav a[href*="design"]')
    .first()
    .waitFor({ timeout: 15000 })
    .then(() => true)
    .catch(() => false);

  if (!ok) {
    console.error('[cloak] login indicator not found — likely soft-blocked');
    await browser.close();
    process.exit(2);
  }

  mkdirSync(CACHE_DIR, { recursive: true });
  await context.storageState({ path: STATE_PATH });
  writeFileSync(META_PATH, JSON.stringify({
    capturedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 14 * 86400 * 1000).toISOString(),
    method: 'cloak'
  }, null, 2));
  await browser.close();
  console.log(`[cloak] storageState saved: ${STATE_PATH}`);
}

main().catch((err) => {
  console.error('[cloak] error:', err.message);
  process.exit(1);
});
```

- [ ] **Step 2: 권한**

```bash
chmod +x scripts/cloak_login.mjs
```

- [ ] **Step 3: smoke test — env 누락 시 명확한 에러**

```bash
node scripts/cloak_login.mjs 2>&1 | head -5
# Expect: "missing env: CLAUDE_LOGIN_EMAIL, CLAUDE_LOGIN_PW" 또는 cloak-browser 자동설치 로그
```

- [ ] **Step 4: Commit**

```bash
git add scripts/cloak_login.mjs
git commit -m "feat(research-design): cloak-browser headless login attempt"
```

---

### Task 9: manual_login.mjs — Tailscale m4 폴백

**Files:**
- Create: `scripts/manual_login.mjs`

- [ ] **Step 1: manual_login.mjs 작성**

```javascript
#!/usr/bin/env node
/**
 * manual_login.mjs
 *   - Tailscale m4 의 Chrome 을 CDP 9222 로 띄움
 *   - 사용자에게 한글 안내 후 Enter 대기
 *   - chromium.connectOverCDP 로 attach, storageState 추출
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import readline from 'node:readline';
import { loadEnv, requireEnv } from '../lib/research_design_env.mjs';

const CACHE_DIR = join(homedir(), '.config', 'research-engine', 'claude-design');
const STATE_PATH = join(CACHE_DIR, 'storageState.json');
const META_PATH = join(CACHE_DIR, 'state.meta.json');
const CDP_PORT = 9222;

function prompt(msg) {
  return new Promise((res) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question(msg, (a) => { rl.close(); res(a); });
  });
}

async function main() {
  const env = loadEnv();
  const { M4_TAILSCALE_HOST, M4_TAILSCALE_USER } = requireEnv(['M4_TAILSCALE_HOST', 'M4_TAILSCALE_USER'], env);

  console.error(`\n[manual] Tailscale ${M4_TAILSCALE_USER}@${M4_TAILSCALE_HOST} 의 Chrome 을 CDP 모드로 띄웁니다…\n`);
  const sshArgs = [
    '-o', 'StrictHostKeyChecking=accept-new',
    '-L', `${CDP_PORT}:127.0.0.1:${CDP_PORT}`,
    `${M4_TAILSCALE_USER}@${M4_TAILSCALE_HOST}`,
    `open -a "Google Chrome" --args --remote-debugging-port=${CDP_PORT} --user-data-dir=/tmp/cdp-claude-design "https://claude.ai/login" && sleep 1800`
  ];
  const ssh = spawn('ssh', sshArgs, { stdio: ['ignore', 'inherit', 'inherit'] });

  await new Promise((r) => setTimeout(r, 5000));

  console.error('Mac m4 의 Chrome 에서 https://claude.ai/login → claude.ai/design 까지 로그인 완료한 뒤 여기서 Enter:');
  await prompt('');

  const { chromium } = await import('playwright');
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${CDP_PORT}`);
  const ctx = browser.contexts()[0];
  if (!ctx) {
    console.error('[manual] no browser context — Chrome 이 떠 있나요?');
    process.exit(1);
  }

  mkdirSync(CACHE_DIR, { recursive: true });
  await ctx.storageState({ path: STATE_PATH });
  writeFileSync(META_PATH, JSON.stringify({
    capturedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 14 * 86400 * 1000).toISOString(),
    method: 'manual-m4'
  }, null, 2));
  console.log(`[manual] storageState saved: ${STATE_PATH}`);

  ssh.kill();
  await browser.close();
}

main().catch((err) => { console.error('[manual] error:', err.message); process.exit(1); });
```

- [ ] **Step 2: 권한**

```bash
chmod +x scripts/manual_login.mjs
```

- [ ] **Step 3: Commit**

```bash
git add scripts/manual_login.mjs
git commit -m "feat(research-design): Tailscale m4 manual login fallback via CDP attach"
```

---

### Task 10: design_collect.mjs

**Files:**
- Create: `scripts/design_collect.mjs`

- [ ] **Step 1: 코드 작성**

```javascript
#!/usr/bin/env node
/**
 * design_collect.mjs <slug>
 *   - storageState 검사 → 유효하면 사용, 아니면 cloak_login → manual_login chain
 *   - claude.ai/design 진입, research/<slug>/README.md 텍스트 + sources 제출
 *   - "Hand off to Claude Code" 클릭, ZIP 다운로드
 *   - research/<slug>/design/handoff/ 에 펼침
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

const CACHE_DIR = join(homedir(), '.config', 'research-engine', 'claude-design');
const STATE_PATH = join(CACHE_DIR, 'storageState.json');
const META_PATH = join(CACHE_DIR, 'state.meta.json');

function stateValid() {
  if (!existsSync(STATE_PATH) || !existsSync(META_PATH)) return false;
  const meta = JSON.parse(readFileSync(META_PATH, 'utf8'));
  return new Date(meta.expiresAt) > new Date();
}

function runLogin(script) {
  const r = spawnSync('node', [`scripts/${script}.mjs`], { stdio: 'inherit' });
  return r.status === 0;
}

async function ensureLogin() {
  if (stateValid()) {
    console.error('[collect] storageState valid — reusing');
    return;
  }
  console.error('[collect] storageState missing/expired — trying cloak_login');
  if (runLogin('cloak_login')) return;
  console.error('[collect] cloak_login failed — falling back to manual_login (Tailscale m4)');
  if (!runLogin('manual_login')) {
    console.error('[collect] all login methods failed');
    process.exit(1);
  }
}

async function collect(slug) {
  const readmePath = `research/${slug}/README.md`;
  if (!existsSync(readmePath)) {
    console.error(`[collect] missing ${readmePath}`);
    process.exit(1);
  }
  const readme = readFileSync(readmePath, 'utf8');

  const handoffDir = `research/${slug}/design/handoff`;
  mkdirSync(handoffDir, { recursive: true });

  const { chromium } = await import('playwright');
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ storageState: STATE_PATH, acceptDownloads: true });
  const page = await ctx.newPage();

  await page.goto('https://claude.ai/design', { waitUntil: 'domcontentloaded' });
  const ok = await page.locator('[data-testid=user-menu], header img[alt*="avatar"], nav a[href*="design"]').first()
    .waitFor({ timeout: 15000 }).then(() => true).catch(() => false);
  if (!ok) {
    console.error('[collect] design 페이지 진입 실패 — storageState 무효 가능. 캐시 폐기 후 재시도하세요.');
    await browser.close();
    process.exit(1);
  }

  // 새 디자인 + 프롬프트 전송 (실 셀렉터는 첫 collect 시 capture 후 patch — spec §6 참조)
  await page.locator('button:has-text("New design"), [data-testid=new-design]').first().click();
  const promptBox = page.locator('textarea, [role=textbox]').first();
  await promptBox.fill(buildPrompt(slug, readme));
  await page.locator('button[type=submit], [data-testid=submit-prompt]').first().click();

  console.error('[collect] 디자인 생성 대기 중 (최대 5분)…');
  await page.locator('button:has-text("Hand off to Claude Code"), [data-testid=handoff]')
    .first().waitFor({ timeout: 300000 });

  await page.screenshot({ path: `${handoffDir}/design-screenshot.png`, fullPage: true });

  const [download] = await Promise.all([
    page.waitForEvent('download', { timeout: 120000 }),
    page.locator('button:has-text("Hand off to Claude Code"), [data-testid=handoff]').first().click()
  ]);

  const zipPath = `${handoffDir}/bundle.zip`;
  await download.saveAs(zipPath);

  spawnSync('unzip', ['-o', zipPath, '-d', handoffDir], { stdio: 'inherit' });
  writeFileSync(`${handoffDir}/.captured-at`, new Date().toISOString());

  await browser.close();
  console.log(`[collect] handoff saved: ${handoffDir}`);
}

function buildPrompt(slug, readme) {
  const trimmed = readme.split('\n').slice(0, 200).join('\n');
  return `다음 research 결과를 인터랙티브 프로토타입(원페이지 또는 멀티페이지)으로 만들어줘. 핵심 메시지와 CTA 가 분명하게, 실서비스 수준의 디자인 시스템(색·타이포·컴포넌트)을 일관되게 적용. 마지막에 'Hand off to Claude Code' 가능한 상태로 마무리.

slug: ${slug}

${trimmed}`;
}

const slug = process.argv[2];
if (!slug) { console.error('usage: design_collect.mjs <slug>'); process.exit(2); }
await ensureLogin();
await collect(slug);
```

- [ ] **Step 2: 권한 + commit**

```bash
chmod +x scripts/design_collect.mjs
git add scripts/design_collect.mjs
git commit -m "feat(research-design): design_collect — login chain → handoff bundle download"
```

> **Note:** 실 셀렉터는 첫 실행 시 잡힐 가능성이 높다. 실패 시 `page.pause()` 또는 inspector 로 셀렉터를 잡고 본 파일을 patch — 그 patch 도 별도 commit (`fix(collect): selectors`).

---

## Phase 3 — handoff parsing + 워커 prompt + scaffold

### Task 11: design_handoff_parser.mjs GREEN

**Files:**
- Modify: `lib/design_handoff_parser.mjs`

- [ ] **Step 1: parser 구현**

```javascript
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, extname } from 'node:path';

export function parseHandoff(bundleDir) {
  const meta = JSON.parse(readFileSync(join(bundleDir, 'handoff.meta.json'), 'utf8'));
  const entries = readdirSync(bundleDir, { withFileTypes: true });

  const pages = [];
  const styles = [];
  const assets = [];

  for (const e of entries) {
    if (!e.isFile()) continue;
    const full = join(bundleDir, e.name);
    if (e.name.endsWith('.html')) {
      pages.push({ name: e.name, html: readFileSync(full, 'utf8') });
    } else if (e.name.endsWith('.css')) {
      styles.push({ name: e.name, css: readFileSync(full, 'utf8') });
    } else if (['.png', '.jpg', '.jpeg', '.svg', '.webp', '.woff', '.woff2'].includes(extname(e.name))) {
      assets.push({ name: e.name, path: full, bytes: statSync(full).size });
    }
  }

  return {
    meta,
    pages,
    styles,
    assets,
    components: meta.components || [],
    designSystem: meta.designSystem || {}
  };
}
```

- [ ] **Step 2: 테스트 PASS 확인**

```bash
pnpm test:unit -- tests/research-design/lib/design_handoff_parser.test.mjs
```

Expected: 4 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/design_handoff_parser.mjs
git commit -m "feat(research-design): handoff bundle parser GREEN"
```

---

### Task 12: app_scaffold.mjs

**Files:**
- Create: `lib/app_scaffold.mjs`
- Create: `tests/research-design/lib/app_scaffold.test.mjs`

- [ ] **Step 1: 테스트 작성 (RED)**

```javascript
import { test, expect } from 'vitest';
import { mkdtempSync, existsSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { scaffoldApp } from '../../../lib/app_scaffold.mjs';
import { parseHandoff } from '../../../lib/design_handoff_parser.mjs';

test('스캐폴드가 Next.js 14 app router 구조를 만든다', () => {
  const dir = mkdtempSync(join(tmpdir(), 'scaffold-'));
  try {
    const handoff = parseHandoff('tests/research-design/fixtures/handoff-stub');
    scaffoldApp({ outDir: dir, handoff, slug: 'fake-slug', title: 'Fake' });
    expect(existsSync(join(dir, 'package.json'))).toBe(true);
    expect(existsSync(join(dir, 'next.config.mjs'))).toBe(true);
    expect(existsSync(join(dir, 'app/layout.tsx'))).toBe(true);
    expect(existsSync(join(dir, 'app/page.tsx'))).toBe(true);
    expect(existsSync(join(dir, 'app/upload/page.tsx'))).toBe(true);
    expect(existsSync(join(dir, 'app/health/route.ts'))).toBe(true);
    expect(existsSync(join(dir, 'public/sample-handoff.html'))).toBe(true);
    expect(existsSync(join(dir, 'app/globals.css'))).toBe(true);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
```

```bash
pnpm test:unit -- tests/research-design/lib/app_scaffold.test.mjs
# Expected: FAIL
```

- [ ] **Step 2: scaffold 구현 (GREEN)**

`lib/app_scaffold.mjs`:

```javascript
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export function scaffoldApp({ outDir, handoff, slug, title }) {
  mkdirSync(join(outDir, 'app'), { recursive: true });
  mkdirSync(join(outDir, 'app/upload'), { recursive: true });
  mkdirSync(join(outDir, 'app/health'), { recursive: true });
  mkdirSync(join(outDir, 'public'), { recursive: true });

  writeFileSync(join(outDir, 'package.json'), JSON.stringify({
    name: slug,
    version: '0.1.0',
    private: true,
    type: 'module',
    scripts: { dev: 'next dev', build: 'next build', start: 'next start -p ${PORT:-3000}' },
    dependencies: { next: '^14.2.0', react: '^18.3.0', 'react-dom': '^18.3.0' },
    devDependencies: { typescript: '^5.5.0', '@types/node': '^22.0.0', '@types/react': '^18.3.0' }
  }, null, 2));

  writeFileSync(join(outDir, 'next.config.mjs'), `export default { reactStrictMode: true };\n`);
  writeFileSync(join(outDir, 'tsconfig.json'), JSON.stringify({
    compilerOptions: { target: 'ES2022', module: 'ESNext', moduleResolution: 'Bundler', jsx: 'preserve', strict: true, esModuleInterop: true, skipLibCheck: true, baseUrl: '.', plugins: [{ name: 'next' }] },
    include: ['next-env.d.ts', '**/*.ts', '**/*.tsx']
  }, null, 2));

  const ds = handoff.designSystem || {};
  const colors = ds.colors || {};
  const css = `:root {\n${Object.entries(colors).map(([k, v]) => `  --${k}: ${v};`).join('\n')}\n}\nbody { background: var(--bg, #fff); color: var(--fg, #000); font-family: ${ds.typography?.base || 'system-ui'}, sans-serif; margin: 0; }\n`;
  writeFileSync(join(outDir, 'app/globals.css'), css);

  writeFileSync(join(outDir, 'app/layout.tsx'),
`import './globals.css';
export const metadata = { title: ${JSON.stringify(title)} };
export default function Root({ children }: { children: React.ReactNode }) {
  return <html lang="en"><body>{children}</body></html>;
}
`);

  writeFileSync(join(outDir, 'app/page.tsx'),
`export default function Home() {
  return (
    <main>
      <header style={{ padding: 48, textAlign: 'center' }}>
        <h1>${title}</h1>
        <p>Turn raster art into clean SVG in seconds.</p>
        <a href="/upload"><button data-testid="cta-try" style={{ padding: '12px 24px', borderRadius: 8 }}>Try free</button></a>
      </header>
    </main>
  );
}
`);

  // upload page — SVG mock 을 JSX 로 직접 렌더 (innerHTML 사용 금지)
  writeFileSync(join(outDir, 'app/upload/page.tsx'),
`'use client';
import { useState } from 'react';
export default function Upload() {
  const [show, setShow] = useState(false);
  function onConvert() { setShow(true); }
  return (
    <main style={{ padding: 48 }}>
      <h2>Upload your image</h2>
      <input type="file" accept="image/*" />
      <button data-testid="convert" onClick={onConvert}>Convert</button>
      <div data-testid="svg-preview">
        {show && (
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40" width={120} height={120}>
            <rect width={40} height={40} fill="var(--accent, #6c4cff)" />
          </svg>
        )}
      </div>
    </main>
  );
}
`);

  writeFileSync(join(outDir, 'app/health/route.ts'),
`export async function GET() { return new Response('ok', { status: 200 }); }\n`);

  if (handoff.pages[0]) {
    writeFileSync(join(outDir, 'public/sample-handoff.html'), handoff.pages[0].html);
  }
}
```

- [ ] **Step 3: 테스트 PASS**

```bash
pnpm test:unit -- tests/research-design/lib/app_scaffold.test.mjs
# Expected: PASS
```

- [ ] **Step 4: Commit**

```bash
git add lib/app_scaffold.mjs tests/research-design/lib/app_scaffold.test.mjs
git commit -m "feat(research-design): Next.js 14 scaffold with design-system injection"
```

---

### Task 13: design-builder agent prompt

**Files:**
- Create: `agents/design-builder.md`

- [ ] **Step 1: prompt 작성**

````markdown
---
name: design-builder
description: research-design 파이프라인의 build worker — handoff bundle 을 받아 Next.js 앱을 production-grade 로 구현. claude-build / codex-build 양 pane 에서 동일 프롬프트로 실행.
---

# design-builder

## 너의 역할

너는 `/research-design` 파이프라인의 **build worker** 다. 너의 출력은 **production-ready Next.js 14 (app router) 앱** 이다.

## 입력 (worktree 안)

- `handoff/` — claude.ai/design 의 raw 출력 (HTML, CSS, asset, handoff.meta.json)
- `scenarios.json` — 통과해야 할 e2e 시나리오 (사람이 사전 정의, 절대 수정 금지)
- 본 plan 의 `lib/app_scaffold.mjs` 는 이미 호출되어 `app/` 의 baseline (모든 e2e selector 의 data-testid 가 들어있음) 이 깔려있다

## 산출물

`./app/` — 다음 조건을 만족하는 Next.js 앱:

1. `pnpm install && pnpm build && pnpm start` 가 에러 없이 작동
2. `scenarios.json` 의 모든 시나리오가 `pnpm test:e2e` 에서 PASS
3. 모든 `[data-testid=…]` 셀렉터가 가리키는 element 가 실제로 존재
4. console.error 없음, network 4xx/5xx 없음
5. 디자인은 `handoff/` 의 design system (색·타이포·컴포넌트) 을 충실히 반영
6. dangerouslySetInnerHTML 금지 — 동적 콘텐츠는 JSX 로

## 작업 규칙

- baseline = scaffold 결과물 그대로
- handoff 의 design system 을 `app/globals.css` 에 더 풍부하게 반영
- handoff 의 페이지 텍스트·레이아웃·components 를 React 컴포넌트로 옮기되 testid 보존
- 매 commit 마다 메시지 prefix: `[builder]`
- 매 변경 후 `pnpm build && pnpm test:e2e` 자체 실행 → 실패 시 본인이 수정. 최대 5 사이클까지.

## 종료 조건

- `pnpm test:e2e` GREEN
- screenshot 캡처 후 `node ../../scripts/judge_app.mjs --app-screenshot ./screenshots/home.png --design-screenshot ../handoff/design-screenshot.png --scenarios ../scenarios.json --out ./judge.json` 출력의 `total >= 75` **그리고** 모든 axis `>= 60`
- 두 조건 만족 시 `./WORKER_DONE` 파일 생성
````

- [ ] **Step 2: Commit**

```bash
git add agents/design-builder.md
git commit -m "feat(research-design): design-builder worker prompt for claude/codex panes"
```

---

### Task 14: design-critic agent prompt

**Files:**
- Create: `agents/design-critic.md`

- [ ] **Step 1: prompt 작성**

````markdown
---
name: design-critic
description: 상대 worker 의 산출물을 비판적으로 review — accept/reject 항목을 명시한 notes.md 생성.
---

# design-critic

## 너의 역할

너는 다른 worker (claude-build 의 결과를 codex-critic 이 보거나, 그 반대) 의 `app/` 을 **비판적**으로 검토한다.

## 입력

- `./peer-app/` — 상대방의 완성된 Next.js 앱
- `./own-app/` — 너 자신(같은 LLM)의 빌드 결과 (비교 baseline)
- `./scenarios.json`, `./handoff/`

## 산출물

`./review-notes.md` — 다음 구조:

```markdown
# Review of <peer> by <self>

## Score read
- peer total: 76.5 (DQ=78, OR=72, CR=80, FN=76)
- own total: 74.0 (DQ=75, OR=70, CR=77, FN=74)

## Accept (병합 시 채택 권고)
- [accept] `app/page.tsx` 의 hero CTA 배치 — own 보다 시각 위계 명확
- [accept] `app/globals.css` 의 color token 네이밍 — handoff design system 과 일치

## Reject (병합 시 거부 권고)
- [reject] `app/upload/page.tsx` 의 useEffect 내부 fetch — own 의 직접 변환 로직이 더 단순
- [reject] `next.config.mjs` 의 image domain — 우리 시나리오엔 불필요한 의존성

## Hazards (양쪽 다 문제, merger 가 별도 처리 필요)
- 둘 다 mobile breakpoint 부재 — 시나리오엔 없으나 production 에서 즉시 보일 결함

## Net verdict
- base: peer / own — 점수 차 작고 accept 항목이 의미 있으므로 peer 를 base 로 권고
```

## 규칙

- 거짓 칭찬·뭉뚱그림 금지. 구체적 파일·줄·행동.
- own 이 더 나은 부분은 명확히 reject 로 표시. 비교 기준은 **시나리오 통과·디자인 일치·코드 명료성** 셋.
- 50줄 이내. 항목 ≥ 5개.
- 본인 own-app 점수도 같이 적어 점수 비교 가능하게.
````

- [ ] **Step 2: Commit**

```bash
git add agents/design-critic.md
git commit -m "feat(research-design): design-critic cross-review prompt"
```

---

### Task 15: design-merger agent prompt

**Files:**
- Create: `agents/design-merger.md`

- [ ] **Step 1: prompt 작성**

````markdown
---
name: design-merger
description: 두 worker 결과 + 두 review notes 를 받아 머지 산출물을 만든다. G2 게이트 통과까지 자체 루프.
---

# design-merger

## 입력

- `./claude-app/`, `./codex-app/` — 두 build 산출물
- `./claude-app/judge.json`, `./codex-app/judge.json` — 자체 채점 결과
- `./claude-review.md`, `./codex-review.md` — 교차 review
- `./handoff/`, `./scenarios.json`

## 산출물

`./merged-app/` — 다음 규칙으로 합쳐진 단일 앱:

1. **base** = `total` 점수 높은 쪽 (동점이면 functionality 점수 우선)
2. **accept 항목 통합**:
   - 양쪽 review 의 `[accept]` 항목만 base 에 patch 형식으로 적용
   - 두 review 의 accept 가 같은 파일에서 충돌하면 → base 측 review 의 accept 우선
   - 충돌 해결 불가능한 항목은 `MERGE_CONFLICTS.md` 에 기록 (그 부분만 base 유지)
3. `[reject]` 항목은 무시
4. `[hazards]` 항목은 `MERGE_HAZARDS.md` 에 모아 남김

## 종료 조건

- `merged-app/` 에서 `pnpm install && pnpm build && pnpm test:e2e` GREEN
- `judge_app.mjs` 의 `total >= 75 && 모든 axis >= 60`
- 5 사이클 안 통과 못 하면 `MERGE_FAILED` 파일 생성 (orchestrator 가 점수 높았던 단일 worker app/ 으로 fallback)
````

- [ ] **Step 2: Commit**

```bash
git add agents/design-merger.md
git commit -m "feat(research-design): design-merger consolidation prompt"
```

---

## Phase 4 — orchestration + judge GREEN

### Task 16: herdr_orchestrate.sh

**Files:**
- Create: `scripts/herdr_orchestrate.sh`

- [ ] **Step 1: 코드 작성**

```bash
#!/usr/bin/env bash
# herdr_orchestrate.sh <slug> <run_dir>
#
# 가정: HERDR_ENV=1, herdr CLI 가 PATH 에.
# pane 4개:
#   1) claude-build : claude -p
#   2) codex-build  : codex exec
#   3) claude-critic: claude -p
#   4) codex-critic : codex exec

set -euo pipefail

SLUG="${1:?slug required}"
RUN_DIR="${2:?run_dir required}"

if [[ -z "${HERDR_ENV:-}" ]]; then
  echo "[orchestrate] HERDR_ENV not set — must run inside herdr session" >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
RESEARCH_DIR="research/${SLUG}"
HANDOFF_DIR="${RESEARCH_DIR}/design/handoff"
SCENARIOS="${RESEARCH_DIR}/design/scenarios.json"

[[ -d "${HANDOFF_DIR}" ]] || { echo "missing ${HANDOFF_DIR}" >&2; exit 1; }
[[ -f "${SCENARIOS}" ]] || { echo "missing ${SCENARIOS}" >&2; exit 1; }

# 4개 worktree 생성 + 컨텍스트 복사
for kind in claude-build codex-build claude-critic codex-critic; do
  wt="${RUN_DIR}/wt-${kind}"
  rm -rf "${wt}"
  git worktree add -d "${wt}" >/dev/null
  mkdir -p "${wt}/run"
  cp -r "${HANDOFF_DIR}" "${wt}/run/handoff"
  cp "${SCENARIOS}" "${wt}/run/scenarios.json"

  # builder pane 만 scaffold 미리 실행
  if [[ "${kind}" == *-build ]]; then
    node -e "
      import('${REPO_ROOT}/lib/design_handoff_parser.mjs').then(p => 
        import('${REPO_ROOT}/lib/app_scaffold.mjs').then(s => {
          const h = p.parseHandoff('${wt}/run/handoff');
          s.scaffoldApp({ outDir: '${wt}/run/app', handoff: h, slug: '${SLUG}', title: h.meta.title || '${SLUG}' });
        })
      );
    "
  fi
done

# pane 생성 + 명령 전송
herdr pane new --name claude-build --cwd "${RUN_DIR}/wt-claude-build/run"
herdr pane send claude-build "claude -p --append-system-prompt \"\$(cat ${REPO_ROOT}/agents/design-builder.md)\" 'build the app per agents/design-builder.md. exit when ./WORKER_DONE exists'"

herdr pane new --name codex-build --cwd "${RUN_DIR}/wt-codex-build/run"
herdr pane send codex-build "codex exec --dangerously-bypass-approvals-and-sandbox --system \"\$(cat ${REPO_ROOT}/agents/design-builder.md)\" 'build the app per agents/design-builder.md. exit when ./WORKER_DONE exists'"

# 두 build pane 종료 대기 (60분 cap)
deadline=$(( $(date +%s) + 3600 ))
while (( $(date +%s) < deadline )); do
  if [[ -f "${RUN_DIR}/wt-claude-build/run/WORKER_DONE" && -f "${RUN_DIR}/wt-codex-build/run/WORKER_DONE" ]]; then
    break
  fi
  sleep 15
done

[[ -f "${RUN_DIR}/wt-claude-build/run/WORKER_DONE" ]] || { echo "[orchestrate] claude-build did not finish" >&2; exit 2; }
[[ -f "${RUN_DIR}/wt-codex-build/run/WORKER_DONE" ]] || { echo "[orchestrate] codex-build did not finish" >&2; exit 2; }

# critic worktree 셋업
cp -r "${RUN_DIR}/wt-codex-build/run/app" "${RUN_DIR}/wt-claude-critic/run/peer-app"
cp -r "${RUN_DIR}/wt-claude-build/run/app" "${RUN_DIR}/wt-claude-critic/run/own-app"
cp -r "${RUN_DIR}/wt-claude-build/run/app" "${RUN_DIR}/wt-codex-critic/run/peer-app"
cp -r "${RUN_DIR}/wt-codex-build/run/app" "${RUN_DIR}/wt-codex-critic/run/own-app"

herdr pane new --name claude-critic --cwd "${RUN_DIR}/wt-claude-critic/run"
herdr pane send claude-critic "claude -p --append-system-prompt \"\$(cat ${REPO_ROOT}/agents/design-critic.md)\" 'review peer-app, write review-notes.md'"

herdr pane new --name codex-critic --cwd "${RUN_DIR}/wt-codex-critic/run"
herdr pane send codex-critic "codex exec --dangerously-bypass-approvals-and-sandbox --system \"\$(cat ${REPO_ROOT}/agents/design-critic.md)\" 'review peer-app, write review-notes.md'"

deadline=$(( $(date +%s) + 1800 ))
while (( $(date +%s) < deadline )); do
  if [[ -f "${RUN_DIR}/wt-claude-critic/run/review-notes.md" && -f "${RUN_DIR}/wt-codex-critic/run/review-notes.md" ]]; then
    break
  fi
  sleep 10
done

echo "[orchestrate] all 4 panes finished" >&2
```

- [ ] **Step 2: 권한 + commit**

```bash
chmod +x scripts/herdr_orchestrate.sh
git add scripts/herdr_orchestrate.sh
git commit -m "feat(research-design): herdr 4-pane orchestrator for parallel build+critic"
```

---

### Task 17: judge_app.mjs real implementation (GREEN)

**Files:**
- Modify: `scripts/judge_app.mjs`

- [ ] **Step 1: real judge 구현 — `claude -p` 호출**

`judge()` 의 mock=false 분기를 다음으로 교체:

```javascript
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const RUBRIC = `
4-axis design rubric. Score each 0-100 strictly. Output JSON only:
{"designQuality": <int>, "originality": <int>, "craft": <int>, "functionality": <int>, "axisNotes": {...}}

- designQuality: visual hierarchy, color harmony, typography, spacing
- originality: 차별성. 흔한 AI 템플릿 같지 않은가
- craft: 디테일 (interaction polish, alignment, micro-typography)
- functionality: scenarios.json 항목들이 잘 작동하는 디자인인가
`;

export async function judge({ appScreenshot, designScreenshot, scenariosPath, mock = false }) {
  if (mock) return { designQuality: 78, originality: 72, craft: 80, functionality: 76, total: 76.5, axisNotes: { designQuality: 'mock', originality: 'mock', craft: 'mock', functionality: 'mock' } };

  const scenarios = readFileSync(scenariosPath, 'utf8');
  const prompt = `${RUBRIC}\n\nApp screenshot path: ${appScreenshot}\nDesign reference path: ${designScreenshot}\nScenarios JSON:\n${scenarios}\n\nOutput JSON only.`;

  const res = spawnSync('claude', ['-p', prompt], { encoding: 'utf8', timeout: 180000 });
  if (res.status !== 0) throw new Error(`claude -p failed: ${res.stderr}`);

  const m = res.stdout.match(/\{[\s\S]*\}/);
  if (!m) throw new Error(`no JSON in claude output: ${res.stdout.slice(0, 200)}`);
  const parsed = JSON.parse(m[0]);

  const total = (parsed.designQuality + parsed.originality + parsed.craft + parsed.functionality) / 4;
  return { ...parsed, total: Math.round(total * 10) / 10 };
}
```

- [ ] **Step 2: 기존 mock 테스트 PASS 유지, real 모드는 smoke 로 분리**

`tests/research-design/lib/judge_app.test.mjs` 에 추가:

```javascript
import { describe } from 'vitest';

describe.skipIf(!process.env.JUDGE_SMOKE)('real judge smoke (set JUDGE_SMOKE=1)', () => {
  test('real call returns valid score shape', async () => {
    const out = await judge({
      appScreenshot: 'tests/research-design/fixtures/handoff-stub/index.html',
      designScreenshot: 'tests/research-design/fixtures/handoff-stub/index.html',
      scenariosPath: 'research/2026-05-22-ai-image-vectorization-service/design/scenarios.json',
      mock: false
    });
    expect(out.total).toBeGreaterThan(0);
    for (const ax of ['designQuality', 'originality', 'craft', 'functionality']) {
      expect(out[ax]).toBeGreaterThanOrEqual(0);
      expect(out[ax]).toBeLessThanOrEqual(100);
    }
  }, 240000);
});
```

- [ ] **Step 3: 기존 RED 테스트 (real 모드 throw 기대) 는 이 task 가 GREEN 으로 만들기 때문에 제거 또는 수정**

`tests/research-design/lib/judge_app.test.mjs` 의 `'real 모드는 구현 전까지 throw'` 테스트 삭제 (이미 구현됨).

- [ ] **Step 4: 실행**

```bash
pnpm test:unit -- tests/research-design/lib/judge_app.test.mjs
```

기본 모드: 1 테스트 PASS (mock). smoke 모드: `JUDGE_SMOKE=1 pnpm test:unit -- judge_app` — 1 추가 PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/judge_app.mjs tests/research-design/lib/judge_app.test.mjs
git commit -m "feat(research-design): judge_app real path via claude -p"
```

---

## Phase 5 — deploy + top-level orchestrator + slash command + E2E

### Task 18: lxc_deploy.sh

**Files:**
- Create: `scripts/lxc_deploy.sh`

- [ ] **Step 1: 코드 작성**

```bash
#!/usr/bin/env bash
# lxc_deploy.sh <slug> <app_dir>
#   - hetzner-master 에 LXC 생성/업데이트
#   - idempotent

set -euo pipefail

SLUG="${1:?slug required}"
APP_DIR="${2:?app_dir required}"

[[ -f .env.research-design ]] && set -a && . .env.research-design && set +a
: "${HETZNER_MASTER_HOST:?}"; : "${HETZNER_MASTER_USER:?}"

CONTAINER_NAME="rd-${SLUG//[^a-z0-9]/-}"
CONTAINER_NAME="${CONTAINER_NAME:0:63}"
REMOTE_APP="/opt/research-design/${SLUG}"

ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "set -e; \
  if ! pct list | awk '{print \$3}' | grep -qx '${CONTAINER_NAME}'; then \
    NEXT_ID=\$(pvesh get /cluster/nextid); \
    pct create \$NEXT_ID local:vztmpl/debian-12-standard_*.tar.zst --hostname ${CONTAINER_NAME} --cores 1 --memory 1024 --rootfs local-lvm:10 --net0 name=eth0,bridge=vmbr0,ip=dhcp --features nesting=1 --unprivileged 1; \
    pct start \$NEXT_ID; \
  fi"

CTID=$(ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "pct list | awk '\$3==\"${CONTAINER_NAME}\" {print \$1}'")
[[ -n "${CTID}" ]] || { echo "[deploy] CTID not found" >&2; exit 1; }

ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "pct exec ${CTID} -- bash -lc '
  set -e
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates gnupg unzip caddy
  if ! command -v node >/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y -qq nodejs
  fi
  npm i -g pnpm@9 >/dev/null
  if ! command -v tailscale >/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  mkdir -p ${REMOTE_APP}
'"

ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "pct exec ${CTID} -- bash -lc '
  if ! tailscale status >/dev/null 2>&1; then
    echo \"[deploy] tailscale not authenticated in container. Run inside container: tailscale up --hostname=${CONTAINER_NAME}\"
    echo \"[deploy] Then re-run lxc_deploy.sh\"
    exit 10
  fi
  tailscale status | head -1
'"

APP_TAR=$(mktemp --suffix=.tar.gz)
tar -czf "${APP_TAR}" -C "${APP_DIR}" .
scp "${APP_TAR}" "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}:/tmp/${CONTAINER_NAME}.tar.gz"
ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "pct push ${CTID} /tmp/${CONTAINER_NAME}.tar.gz /tmp/app.tar.gz && pct exec ${CTID} -- bash -lc 'tar -xzf /tmp/app.tar.gz -C ${REMOTE_APP} && cd ${REMOTE_APP} && pnpm install --frozen-lockfile && pnpm build'"
rm -f "${APP_TAR}"

ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "pct exec ${CTID} -- bash -lc '
  cat > /etc/systemd/system/research-design-app.service <<EOF
[Unit]
Description=research-design app (${SLUG})
After=network.target
[Service]
WorkingDirectory=${REMOTE_APP}
Environment=PORT=3000
ExecStart=/usr/bin/pnpm start
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now research-design-app.service
  systemctl restart research-design-app.service

  cat > /etc/caddy/Caddyfile <<EOF
:443 {
  reverse_proxy 127.0.0.1:3000
  tls internal
}
:80 {
  redir https://{host}{uri}
}
EOF
  systemctl restart caddy
'"

HOST=$(ssh "${HETZNER_MASTER_USER}@${HETZNER_MASTER_HOST}" "pct exec ${CTID} -- tailscale status --json | jq -r '.Self.DNSName // .Self.HostName'")
echo "${HOST}"
```

- [ ] **Step 2: 권한 + commit**

```bash
chmod +x scripts/lxc_deploy.sh
git add scripts/lxc_deploy.sh
git commit -m "feat(research-design): hetzner-master LXC deploy — Debian 12 + Node 22 + Caddy + Tailscale"
```

---

### Task 19: research_design_pipeline.sh (top-level)

**Files:**
- Create: `scripts/research_design_pipeline.sh`

- [ ] **Step 1: 코드 작성**

```bash
#!/usr/bin/env bash
# research_design_pipeline.sh <slug> [--no-deploy] [--login-headful] [--fresh]

set -euo pipefail

SLUG=""
NO_DEPLOY=0
LOGIN_HEADFUL=0
FRESH=0

for a in "$@"; do
  case "$a" in
    --no-deploy) NO_DEPLOY=1 ;;
    --login-headful) LOGIN_HEADFUL=1 ;;
    --fresh) FRESH=1 ;;
    --*) echo "unknown flag $a" >&2; exit 2 ;;
    *) SLUG="$a" ;;
  esac
done

[[ -n "${SLUG}" ]] || { echo "slug required" >&2; exit 2; }
[[ -f "research/${SLUG}/README.md" ]] || { echo "missing research/${SLUG}/README.md" >&2; exit 1; }
[[ -f "research/${SLUG}/design/scenarios.json" ]] || { echo "missing research/${SLUG}/design/scenarios.json" >&2; exit 1; }

ISO="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RUN_DIR="research/${SLUG}/design/runs/${ISO}"
mkdir -p "${RUN_DIR}"
LOG="${RUN_DIR}/log.jsonl"
log() { jq -nc --arg t "$(date -u +%FT%TZ)" --arg s "$1" --arg m "$2" '{ts:$t,step:$s,msg:$m}' >> "${LOG}"; }

if [[ "${RESEARCH_DESIGN_MOCK:-}" == "1" ]]; then
  log start mock-mode
  log finish mock-mode
  echo "[mock] pipeline run finished" >&2
  exit 0
fi

log start "slug=${SLUG}"

if [[ "${FRESH}" == "1" ]]; then
  rm -f "${HOME}/.config/research-engine/claude-design/storageState.json" || true
fi

if [[ "${LOGIN_HEADFUL}" == "1" ]]; then
  log login.manual ""
  node scripts/manual_login.mjs || { log fatal "manual_login failed"; exit 1; }
fi

log collect.start ""
node scripts/design_collect.mjs "${SLUG}" 2>&1 | tee -a "${RUN_DIR}/collect.log"
log collect.done ""

log orchestrate.start ""
bash scripts/herdr_orchestrate.sh "${SLUG}" "${RUN_DIR}"
log orchestrate.done ""

for kind in claude-build codex-build; do
  WT="${RUN_DIR}/wt-${kind}/run"
  if [[ ! -f "${WT}/WORKER_DONE" ]]; then
    log g1.fail "${kind} no WORKER_DONE"
    exit 2
  fi
  J="${WT}/app/judge.json"
  [[ -f "${J}" ]] || { log g1.fail "${kind} no judge.json"; exit 2; }
  TOTAL=$(jq '.total' "${J}")
  log g1.ok "${kind} total=${TOTAL}"
done

MERGE_WT="${RUN_DIR}/wt-merge"
git worktree add -d "${MERGE_WT}" >/dev/null
mkdir -p "${MERGE_WT}/run"
cp -r "${RUN_DIR}/wt-claude-build/run/app" "${MERGE_WT}/run/claude-app"
cp -r "${RUN_DIR}/wt-codex-build/run/app" "${MERGE_WT}/run/codex-app"
cp "${RUN_DIR}/wt-claude-critic/run/review-notes.md" "${MERGE_WT}/run/claude-review.md"
cp "${RUN_DIR}/wt-codex-critic/run/review-notes.md" "${MERGE_WT}/run/codex-review.md"
cp -r "research/${SLUG}/design/handoff" "${MERGE_WT}/run/handoff"
cp "research/${SLUG}/design/scenarios.json" "${MERGE_WT}/run/scenarios.json"

herdr pane new --name merger --cwd "${MERGE_WT}/run"
herdr pane send merger "claude -p --append-system-prompt \"\$(cat $(pwd)/agents/design-merger.md)\" 'merge per agents/design-merger.md until G2 GREEN'"

deadline=$(( $(date +%s) + 1800 ))
while (( $(date +%s) < deadline )); do
  [[ -d "${MERGE_WT}/run/merged-app" ]] && break
  sleep 10
done
[[ -d "${MERGE_WT}/run/merged-app" ]] || { log g2.fail "merger no merged-app"; exit 3; }

pushd "${MERGE_WT}/run/merged-app" >/dev/null
pnpm install --frozen-lockfile
pnpm build
E2E_BASE_URL=http://localhost:3000 pnpm start &
APP_PID=$!
sleep 5
E2E_PASS=0
if E2E_BASE_URL=http://localhost:3000 pnpm --prefix "$(git rev-parse --show-toplevel)" test:e2e; then E2E_PASS=1; fi
kill "${APP_PID}" || true
popd >/dev/null
[[ "${E2E_PASS}" == "1" ]] || { log g2.fail "merged e2e failed"; exit 3; }
log g2.ok ""

rm -rf "research/${SLUG}/design/app"
cp -r "${MERGE_WT}/run/merged-app" "research/${SLUG}/design/app"
log stamp.done ""

if [[ "${NO_DEPLOY}" == "1" ]]; then
  log deploy.skipped ""
else
  HOST=$(bash scripts/lxc_deploy.sh "${SLUG}" "research/${SLUG}/design/app")
  echo "${HOST}" > "${RUN_DIR}/host.txt"
  log deploy.done "host=${HOST}"

  if [[ -n "${HOST}" ]]; then
    sleep 10
    if E2E_BASE_URL="https://${HOST}" pnpm test:e2e; then
      log g3.ok "host=${HOST}"
    else
      log g3.fail "host=${HOST}"
      exit 4
    fi
  fi
fi

{
  echo "# ${SLUG} design"
  echo
  echo "- run: ${ISO}"
  [[ -f "${RUN_DIR}/host.txt" ]] && echo "- host: $(cat ${RUN_DIR}/host.txt)"
  echo "- gates: $(jq -s 'map(select(.step | startswith(\"g\"))) | map(.step + \"=\" + .msg) | join(\", \")' "${LOG}")"
} > "research/${SLUG}/design/README.md"

log finish ok
echo "[pipeline] done — ${RUN_DIR}"
```

- [ ] **Step 2: 권한 + pipeline.test.sh GREEN 확인**

```bash
chmod +x scripts/research_design_pipeline.sh
pnpm test:bats
```

Expected: 4 tests PASS (mock 모드).

- [ ] **Step 3: Commit**

```bash
git add scripts/research_design_pipeline.sh
git commit -m "feat(research-design): top-level orchestrator with G1/G2/G3 gates"
```

---

### Task 20: commands/research-design.md

**Files:**
- Create: `commands/research-design.md`

- [ ] **Step 1: 명령 작성**

````markdown
---
description: research/<slug>/README.md 를 claude.ai/design 으로 디자인 → claude/codex 병렬 빌드 → hetzner-master LXC 배포
argument-hint: <slug> [--no-deploy] [--login-headful] [--fresh]
---

# /research-design

research-engine 의 완료된 research 세션을 받아 실서비스급 인터랙티브 프로토타입을 만들고 hetzner-master 의 LXC 컨테이너에 배포한다.

## Usage

```
/research-design 2026-05-22-ai-image-vectorization-service
/research-design <slug> --no-deploy
/research-design <slug> --login-headful
/research-design <slug> --fresh
```

## Pre-conditions

1. `research/<slug>/README.md` 존재
2. `research/<slug>/design/scenarios.json` 존재 — TDD 게이트 입력
3. `.env.research-design` 에 자격증명 + Tailscale 정보
4. 실행 환경: `HERDR_ENV=1` (herdr 세션 안)

## Output

- `research/<slug>/design/handoff/` — raw claude.ai/design export
- `research/<slug>/design/app/` — 최종 머지된 Next.js 앱
- `research/<slug>/design/runs/<ISO>/` — 단계별 산출물 + log.jsonl + gate JSON
- Tailscale internal URL — `research/<slug>/design/runs/<ISO>/host.txt`

## Implementation

```
$ bash scripts/research_design_pipeline.sh "$ARGUMENTS"
```

자세한 흐름은 `docs/superpowers/specs/2026-05-22-research-design-bridge.md` 참조.
````

- [ ] **Step 2: Commit**

```bash
git add commands/research-design.md
git commit -m "feat(research-design): /research-design slash command"
```

---

### Task 21: README + CHANGELOG + DEVELOPMENT.md 업데이트

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `DEVELOPMENT.md`

- [ ] **Step 1: README.md slash commands 섹션에 추가**

```
/research-design <slug>                                    # research → claude.ai/design → LXC 배포
/research-design <slug> --no-deploy
/research-design <slug> --login-headful
/research-design <slug> --fresh
```

이어서 의존성 섹션 추가:

```markdown
### Optional: `/research-design` deps

- Node 22 + pnpm 9, `pnpm install`
- Playwright chromium: `pnpm exec playwright install chromium --with-deps`
- cloak-browser (lazy install)
- `.env.research-design` (`.env.research-design.example` 참조)
- herdr session (`HERDR_ENV=1`), Tailscale, hetzner-master ssh
```

- [ ] **Step 2: CHANGELOG.md 에 0.11.0 entry**

```markdown
## [0.11.0]

### Added
- `/research-design <slug>` — claude.ai/design 자동화 → claude/codex 병렬 빌드 → hetzner-master LXC 배포
- 3중 게이트: Playwright e2e + 4축 LLM judge (G1/G2/G3)
- cloak-browser 자동 로그인 → Tailscale m4 수동 폴백
```

- [ ] **Step 3: DEVELOPMENT.md 에 테스트 가이드**

````markdown
### research-design tests

```bash
pnpm install
pnpm exec playwright install chromium --with-deps
pnpm test:unit         # vitest — schema, parser, scaffold, judge mock
pnpm test:bats         # bats — pipeline mock mode
pnpm test:e2e          # playwright — RED until app running
JUDGE_SMOKE=1 pnpm test:unit -- judge_app   # real judge via claude -p
```
````

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md DEVELOPMENT.md
git commit -m "docs(research-design): README + CHANGELOG 0.11.0 + DEVELOPMENT guide"
```

---

### Task 22: 시드 슬러그 e2e 실행 — discovery + 패치

이 task 는 실 환경 적용 — 셀렉터 잡기, 실패 모드 patch.

- [ ] **Step 1: 전제 확인**

```bash
node -v
pnpm -v
which herdr && echo "$HERDR_ENV"
which claude
which codex
test -f .env.research-design && echo OK
cat research/2026-05-22-ai-image-vectorization-service/README.md | head -3
```

- [ ] **Step 2: mock sanity**

```bash
RESEARCH_DESIGN_MOCK=1 bash scripts/research_design_pipeline.sh 2026-05-22-ai-image-vectorization-service
```

- [ ] **Step 3: collect 단독 실행 — 실셀렉터 발견**

```bash
node scripts/design_collect.mjs 2026-05-22-ai-image-vectorization-service
```

처음 실행 — cloak_login 실패 후 manual_login (Tailscale m4) 폴백 가능성 큼. 셀렉터 안 잡히면 design_collect.mjs 에 `await page.pause()` 추가 → playwright inspector 로 셀렉터 잡고 patch → `fix(collect): adjust selectors for current claude.ai/design DOM` 별도 commit.

- [ ] **Step 4: 전체 실행**

```bash
bash scripts/research_design_pipeline.sh 2026-05-22-ai-image-vectorization-service
```

- [ ] **Step 5: 게이트 통과 후 URL 검증**

```bash
HOST=$(cat research/2026-05-22-ai-image-vectorization-service/design/runs/*/host.txt | tail -1)
curl -sS "https://${HOST}/health"
curl -sS "https://${HOST}" | head -20
```

- [ ] **Step 6: 최종 commit**

```bash
git add research/2026-05-22-ai-image-vectorization-service/design/README.md
git commit -m "chore(research-design): seed slug first e2e — design/README artifact

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

### 1. Spec coverage

| Spec 섹션 | 구현 Task |
|---|---|
| §2 목적 | T22 |
| §3 입출력 | T1, T19, T20 |
| §4 G1/G2/G3 | T2, T4, T19 |
| §5.1 모듈 책임 | T8–T20 |
| §5.2 데이터 흐름 | T19 (orchestrator) |
| §6 인증 chain | T8, T9, T10 |
| §7.1 e2e scenarios | T1, T2 |
| §7.2 4축 judge | T4, T17 |
| §7.3 unit/integration | T3, T5 |
| §7.4 RED 순서 | Phase 1 (T1–T5) |
| §8 오류처리표 | T8, T19 (exit codes) |
| §9 외부 의존성 | T1 (package.json), T21 (README) |
| §10 LXC 사양 | T18 |
| §11 YAGNI | (의도적 비포함) |
| §12 추정값 | T7 (env), T21 (README env) |

빠진 항목 없음.

### 2. Placeholder scan

본 plan 안:
- "TBD" / "TODO" / "fill in later" → 없음
- "implement later" → T22 의 셀렉터 patch 는 first-run discovery 의 본질이라 명시
- "Similar to Task N" → 없음 (각 task 별 코드 명시)

### 3. Type / signature consistency

- `parseHandoff(bundleDir)` → T3 fixture, T11 구현, T16 orchestrator 의 inline 호출 모두 같음
- `scaffoldApp({ outDir, handoff, slug, title })` → T12 정의, T16 inline 호출 일치
- `judge({ appScreenshot, designScreenshot, scenariosPath, mock })` → T4 / T17 일치
- `loadEnv(path)`, `requireEnv(keys, env)` → T7 정의, T8 / T9 사용 일치
- exit code: 1=usage/precondition, 2=g1, 3=g2, 4=g3 — T19 일관
- WORKER_DONE / MERGE_FAILED 파일 이름 — T13 / T15 / T16 / T19 일치
- 한 가지 정리: T2 의 runner 는 path 인자만 받고, scenarios.json 의 `$schema` 상대경로는 T1 의 path 와 일치 (`../../../tests/...`)

### 4. 보강 사항

- T11 의 GREEN 전에 fixture handoff.meta.json 의 designSystem.typography.base 가 `system-ui` 인 것을 T12 의 globals.css template 이 같은 키 경로로 읽음 — `handoff.designSystem.typography?.base` 일치 확인 완료
- T17 의 real judge 가 screenshot 이미지 첨부 없이 path 만 prompt 에 — claude -p 가 path 를 'see' 하진 못함. 첫 실행에서 score 안 나오면 image base64 prompt 로 patch → T22 discovery 범위

---

## Plan complete

Plan saved to `docs/superpowers/plans/2026-05-22-research-design-bridge.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — task 별 fresh subagent dispatch, 두 단계 review
2. **Inline Execution** — 본 세션에서 executing-plans 로 batch + checkpoint

다음 메시지에서 선택해주세요.
