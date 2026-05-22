#!/usr/bin/env node
/**
 * Resume into existing design URL, poll until all todos are checked
 * (or 30 min), then download project zip via Share menu.
 */
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SLUG = process.argv[2];
const URL = process.argv[3];
if (!SLUG || !URL) { console.error('usage: wait_and_download.mjs <slug> <url>'); process.exit(2); }

const STATE_PATH = join(homedir(), '.config', 'research-engine', 'claude-design', 'storageState.json');
const HANDOFF_DIR = `research/${SLUG}/design/handoff`;
const SHOT_DIR = `${HANDOFF_DIR}/_run2_wait`;
mkdirSync(SHOT_DIR, { recursive: true });

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ storageState: STATE_PATH, acceptDownloads: true });
const page = await ctx.newPage();

let shotIdx = 0;
const shot = async (name) => {
  shotIdx++;
  await page.screenshot({ path: `${SHOT_DIR}/${String(shotIdx).padStart(2,'0')}-${name}.png`, fullPage: false });
  console.error(`[shot] ${name}`);
};

console.error('[1] resume...');
await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
await page.waitForTimeout(3000);

const STEP_S = 30;
const MAX_S = 30 * 60;
let lastTodoState = '';

for (let elapsed = 0; elapsed < MAX_S; elapsed += STEP_S) {
  // count unchecked todos (checkbox icons with `+` prefix)
  // The todos appear as items in a list — each starts with `+ `.
  const todoTexts = await page.locator('text=/^\\s*\\+\\s/').allInnerTexts().catch(() => []);
  const checkedTexts = await page.locator('[aria-checked=true], input[type=checkbox]:checked + *').allInnerTexts().catch(() => []);

  // file tree under PAGES section
  const pages = await page.locator('text=/^.+\\.html?$/').allInnerTexts().catch(() => []);

  const state = `todos=${todoTexts.length} checked=${checkedTexts.length} pages=${pages.length}`;
  if (state !== lastTodoState) {
    console.error(`[${elapsed}s] ${state} pages=${JSON.stringify(pages.slice(0,5))}`);
    lastTodoState = state;
  }

  // handle "Questions timed out" chip
  const chip = page.locator('text=/Questions timed out; go with defaults/i').first();
  if (await chip.isVisible({ timeout: 200 }).catch(() => false)) {
    console.error(`[${elapsed}s] timeout chip clicked`);
    await chip.click().catch(() => {});
    await page.waitForTimeout(2000);
  }

  if (elapsed % 120 === 0) await shot(`poll-${String(elapsed).padStart(4,'0')}s`);

  // Check completion signal: at least 3 pages (index, landing, upload, health) AND no spinner text
  if (pages.length >= 3) {
    console.error(`[${elapsed}s] ${pages.length} pages found — break poll`);
    break;
  }
  // alternative: see if "Polish" todo is done
  const polishDone = await page.locator('text=/Polish.*Claude Code handoff/i').first().isVisible({ timeout: 100 }).catch(() => false);
  // (not reliable, just probe)

  await page.waitForTimeout(STEP_S * 1000);
}

console.error('[2] full-page snapshot for judge...');
await page.screenshot({ path: `${HANDOFF_DIR}/design-screenshot.png`, fullPage: true });

console.error('[3] Share menu → Download project as .zip...');
const shareBtn = page.locator('button:has-text("Share")').first();
await shareBtn.click();
await page.waitForTimeout(700);
await shot('share-open');

const dlZip = page.locator('text=/Download project as .zip/i').first();
const [zipDl] = await Promise.all([
  page.waitForEvent('download', { timeout: 60000 }).catch(() => null),
  dlZip.click()
]);

if (zipDl) {
  const zp = `${HANDOFF_DIR}/project-v2.zip`;
  await zipDl.saveAs(zp);
  console.error(`[3] saved: ${zp}`);
  spawnSync('unzip', ['-o', '-q', zp, '-d', HANDOFF_DIR], { stdio: 'inherit' });
  console.error('[3] extracted');
} else {
  console.error('[3-fail] download did not trigger');
  await shot('no-download');
}

// also capture the handoff API URL from the Handoff modal (so we have it for record)
console.error('[4] capture Handoff API URL...');
await page.keyboard.press('Escape').catch(() => {});
await page.waitForTimeout(500);
await shareBtn.click();
await page.waitForTimeout(500);
const handoff = page.locator('text=/Handoff to Claude Code/i').first();
if (await handoff.isVisible({ timeout: 1500 }).catch(() => false)) {
  await handoff.click();
  await page.waitForTimeout(1500);
  const cmd = await page.locator('text=/https:\\/\\/api\\.anthropic\\.com\\/v1\\/design\\/h\\/[A-Za-z0-9]+/').first().textContent().catch(() => '');
  if (cmd) {
    writeFileSync(`${HANDOFF_DIR}/handoff-api-url.txt`, cmd.trim() + '\n');
    console.error('[4] handoff URL saved:', cmd.trim());
  }
}

writeFileSync(`${HANDOFF_DIR}/.captured-at`, new Date().toISOString());
await browser.close();
console.log('[done]');
