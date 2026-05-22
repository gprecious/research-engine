#!/usr/bin/env node
/**
 * Inline T22 collect — discovery version that adapts to live claude.ai/design DOM.
 * Hand-written to bypass the cloak/manual chain since storageState is already valid.
 */
import { chromium } from 'playwright';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SLUG = process.argv[2];
if (!SLUG) { console.error('usage: collect_e2e.mjs <slug>'); process.exit(2); }

const STATE_PATH = join(homedir(), '.config', 'research-engine', 'claude-design', 'storageState.json');
const HANDOFF_DIR = `research/${SLUG}/design/handoff`;
mkdirSync(HANDOFF_DIR, { recursive: true });

const readme = readFileSync(`research/${SLUG}/README.md`, 'utf8');
const prompt = `다음 research 결과를 인터랙티브 프로토타입으로 만들어줘. 핵심 메시지와 CTA 분명하게, 실서비스 수준의 디자인 시스템을 일관되게. 마지막에 'Hand off to Claude Code' 가능한 상태로.

slug: ${SLUG}

${readme.split('\n').slice(0, 200).join('\n')}`;

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ storageState: STATE_PATH, acceptDownloads: true });
const page = await ctx.newPage();

const shot = async (name) => {
  await page.screenshot({ path: `${HANDOFF_DIR}/_probe-${name}.png`, fullPage: false });
  console.error(`[shot] ${name} — url=${page.url()}`);
};

console.error('[1] navigate to /design...');
await page.goto('https://claude.ai/design', { waitUntil: 'networkidle', timeout: 30000 });
await page.waitForTimeout(2000);
await shot('01-dashboard');

console.error('[2] fill Project name...');
const nameInput = page.locator('input[placeholder*="Project name" i], input[placeholder*="name" i]').first();
await nameInput.fill(SLUG);

console.error('[3] select High fidelity...');
// click the High fidelity card/button (vs Wireframe default)
const hiFi = page.locator('text=/High[ \\u00a0]?fidelity/i').first();
if (await hiFi.count() > 0) {
  await hiFi.click();
}

await shot('02-form-filled');

console.error('[4] click Create...');
const createBtn = page.locator('button:has-text("Create")').first();
await createBtn.waitFor({ state: 'visible', timeout: 5000 });
await createBtn.click();

console.error('[5] wait for design workspace (URL change)...');
try {
  await page.waitForURL(/\/design\/.+/, { timeout: 30000 });
} catch {
  console.error('[5b] URL did not change — staying on /design');
}
await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
await page.waitForTimeout(3000);
await shot('03-workspace');

console.error('[6] find prompt textarea + send research prompt...');
// Common candidates: textarea, [contenteditable=true], [role=textbox]
const promptBox = page.locator('textarea, [role=textbox], [contenteditable=true]').first();
await promptBox.waitFor({ state: 'visible', timeout: 15000 });
await promptBox.fill(prompt);
await shot('04-prompt-typed');

// submit — usually Enter or a Send button
const sendBtn = page.locator('button[aria-label*=send i], button:has-text("Send"), button[type="submit"]').first();
if (await sendBtn.count() > 0) {
  await sendBtn.click();
} else {
  await promptBox.press('Enter');
}
console.error('[7] design generation underway — polling for "Hand off" (max 8 min)...');

const handoffBtn = page.locator(
  'button:has-text("Hand off to Claude Code"), button:has-text("Hand off"), [data-testid*=handoff], [data-testid*=hand-off]'
).first();

let handoffFound = false;
for (let i = 0; i < 96; i++) {
  if (await handoffBtn.count() > 0 && await handoffBtn.isVisible().catch(() => false)) {
    handoffFound = true; break;
  }
  if (i % 6 === 0) {
    await shot(`05-generating-${String(i).padStart(2, '0')}`);
  }
  await page.waitForTimeout(5000);
}
if (!handoffFound) {
  console.error('[7-fail] Hand off button never appeared — saving final screenshot');
  await shot('99-final');
  await browser.close();
  process.exit(3);
}

console.error('[8] Hand off button found — capturing design screenshot then clicking...');
await page.screenshot({ path: `${HANDOFF_DIR}/design-screenshot.png`, fullPage: true });

// listen for download triggered by hand-off click
const [download] = await Promise.all([
  page.waitForEvent('download', { timeout: 120000 }).catch(() => null),
  handoffBtn.click()
]);

if (download) {
  const zipPath = `${HANDOFF_DIR}/bundle.zip`;
  await download.saveAs(zipPath);
  console.error('[9] bundle downloaded:', zipPath);
  spawnSync('unzip', ['-o', zipPath, '-d', HANDOFF_DIR], { stdio: 'inherit' });
} else {
  console.error('[9] no download triggered — handoff may have opened a new page or modal');
  await shot('06-after-handoff-click');
  // try detecting opened modal/page link
  await page.waitForTimeout(5000);
  await shot('07-after-handoff-wait');
}

writeFileSync(`${HANDOFF_DIR}/.captured-at`, new Date().toISOString());
await browser.close();
console.log(`[done] handoff dir: ${HANDOFF_DIR}`);
