#!/usr/bin/env node
/**
 * Resume into existing design URL, wait for completion, find Hand off.
 */
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SLUG = process.argv[2];
const DESIGN_URL = process.argv[3];
if (!SLUG || !DESIGN_URL) {
  console.error('usage: _collect_e2e_resume.mjs <slug> <design-url>');
  process.exit(2);
}
const STATE_PATH = join(homedir(), '.config', 'research-engine', 'claude-design', 'storageState.json');
const HANDOFF_DIR = `research/${SLUG}/design/handoff`;
mkdirSync(HANDOFF_DIR, { recursive: true });

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ storageState: STATE_PATH, acceptDownloads: true });
const page = await ctx.newPage();

const shot = async (name) => {
  await page.screenshot({ path: `${HANDOFF_DIR}/_resume-${name}.png`, fullPage: false });
  console.error(`[shot] ${name} — url=${page.url()}`);
};

console.error('[1] resume into design URL...');
await page.goto(DESIGN_URL, { waitUntil: 'networkidle', timeout: 30000 });
await page.waitForLoadState('networkidle').catch(() => {});
await page.waitForTimeout(3000);
await shot('01-resumed');

// Poll up to 30 minutes for design completion + handoff availability
const MAX_MIN = 30;
const STEP_S = 15;
const steps = (MAX_MIN * 60) / STEP_S;

async function tryHandoff() {
  // 1) direct visible hand off button
  const directBtn = page.locator(
    'button:has-text("Hand off to Claude Code"), button:has-text("Hand off"), [data-testid*=handoff i], [data-testid*=hand-off i]'
  ).first();
  if (await directBtn.isVisible({ timeout: 500 }).catch(() => false)) {
    return directBtn;
  }
  // 2) open Share menu (top-right "Share" button) then look inside
  const shareBtn = page.locator('button:has-text("Share")').first();
  if (await shareBtn.isVisible({ timeout: 500 }).catch(() => false)) {
    await shareBtn.click().catch(() => {});
    await page.waitForTimeout(800);
    const insideShare = page.locator(
      'text=/Hand off to Claude Code/i, button:has-text("Hand off"), [role=menuitem]:has-text("Hand off")'
    ).first();
    if (await insideShare.isVisible({ timeout: 500 }).catch(() => false)) {
      return insideShare;
    }
    // close share menu by pressing Escape so subsequent probes work
    await page.keyboard.press('Escape').catch(() => {});
  }
  return null;
}

let target = null;
for (let i = 0; i < steps; i++) {
  target = await tryHandoff();
  if (target) {
    console.error(`[2] hand off element found after ${i*STEP_S}s`);
    break;
  }
  if (i % 4 === 0) {
    await shot(`02-wait-${String(i).padStart(3,'0')}`);
    // dump some progress text
    const todoTxt = await page.locator('text=/Verify and ship|verify-and-ship|All done|Completed/i').count();
    console.error(`[poll] ${i*STEP_S}s elapsed, verify-text count=${todoTxt}`);
  }
  await page.waitForTimeout(STEP_S * 1000);
}

if (!target) {
  console.error('[fail] hand off element never appeared within 30 min');
  await shot('99-timeout');
  await browser.close();
  process.exit(3);
}

console.error('[3] design-screenshot full-page snapshot...');
await page.screenshot({ path: `${HANDOFF_DIR}/design-screenshot.png`, fullPage: true });

console.error('[4] clicking hand off — listening for download / new page / modal...');
const [download, popup] = await Promise.all([
  page.waitForEvent('download', { timeout: 60000 }).catch(() => null),
  ctx.waitForEvent('page', { timeout: 60000 }).catch(() => null),
  target.click()
]);

if (download) {
  const zipPath = `${HANDOFF_DIR}/bundle.zip`;
  await download.saveAs(zipPath);
  console.error('[5] bundle downloaded:', zipPath);
  spawnSync('unzip', ['-o', zipPath, '-d', HANDOFF_DIR], { stdio: 'inherit' });
} else {
  console.error('[5] no download — checking for popup/modal...');
  await page.waitForTimeout(5000);
  await shot('03-after-click');
  if (popup) {
    await popup.waitForLoadState('domcontentloaded').catch(() => {});
    console.error('[5b] popup url:', popup.url());
    await popup.screenshot({ path: `${HANDOFF_DIR}/_popup.png`, fullPage: true });
  }
}

writeFileSync(`${HANDOFF_DIR}/.captured-at`, new Date().toISOString());
console.log(`[done] handoff dir: ${HANDOFF_DIR}`);
await browser.close();
