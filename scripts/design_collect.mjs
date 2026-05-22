#!/usr/bin/env node
/**
 * design_collect.mjs <slug>
 *   - storageState 검사 → 유효하면 사용, 아니면 cloak_login → manual_login chain
 *   - claude.ai/design 진입, research/<slug>/README.md 텍스트 제출
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
    console.error('[collect] design 페이지 진입 실패 — storageState 무효 가능. 캐시 폐기 후 재시도.');
    await browser.close();
    process.exit(1);
  }

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
