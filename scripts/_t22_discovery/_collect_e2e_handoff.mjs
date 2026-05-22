#!/usr/bin/env node
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SLUG = process.argv[2];
const DESIGN_URL = process.argv[3];
const STATE_PATH = join(homedir(), '.config', 'research-engine', 'claude-design', 'storageState.json');
const HANDOFF_DIR = `research/${SLUG}/design/handoff`;
mkdirSync(HANDOFF_DIR, { recursive: true });

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ storageState: STATE_PATH, acceptDownloads: true });
const page = await ctx.newPage();

const shot = async (name) => {
  await page.screenshot({ path: `${HANDOFF_DIR}/_handoff-${name}.png`, fullPage: false });
  console.error(`[shot] ${name}`);
};

console.error('[1] resume...');
await page.goto(DESIGN_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
await page.waitForTimeout(2500);
await shot('01-loaded');

// design-screenshot for judge
console.error('[2] full-page screenshot...');
await page.screenshot({ path: `${HANDOFF_DIR}/design-screenshot.png`, fullPage: true });

console.error('[3] open Share menu...');
const shareBtn = page.locator('button:has-text("Share")').first();
await shareBtn.click();
await page.waitForTimeout(1000);
await shot('02-share-open');

// also try downloading .zip in parallel — it's a stable export
console.error('[4] click "Download project as .zip" (most reliable export)...');
const dlZipItem = page.locator('text=/Download project as .zip/i').first();

let zipDownloaded = false;
if (await dlZipItem.isVisible({ timeout: 3000 }).catch(() => false)) {
  const [zipDl] = await Promise.all([
    page.waitForEvent('download', { timeout: 60000 }).catch(() => null),
    dlZipItem.click()
  ]);
  if (zipDl) {
    const zipPath = `${HANDOFF_DIR}/project.zip`;
    await zipDl.saveAs(zipPath);
    spawnSync('unzip', ['-o', zipPath, '-d', HANDOFF_DIR], { stdio: 'inherit' });
    zipDownloaded = true;
    console.error('[4] zip downloaded + extracted');
  }
}

// re-open Share menu (it may have closed) and click "Handoff to Claude Code…"
await page.waitForTimeout(1500);
console.error('[5] open Share menu again for Handoff...');
await shareBtn.click().catch(() => {});
await page.waitForTimeout(1000);
await shot('03-share-reopen');

const handoffItem = page.locator('text=/Handoff to Claude Code/i').first();
if (await handoffItem.isVisible({ timeout: 3000 }).catch(() => false)) {
  console.error('[5] Handoff to Claude Code clicked...');
  await handoffItem.click();
  await page.waitForTimeout(3000);
  await shot('04-handoff-modal');
  // dump visible modal text
  const modalTexts = await page.locator('[role=dialog]:visible, .modal:visible').allInnerTexts();
  console.error('[5] handoff modal text:', modalTexts.join(' | ').slice(0, 500));
  // try to find any visible download / copy button
  const copyBtn = page.locator('button:has-text("Copy"), button:has-text("Download")').first();
  if (await copyBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
    // listen for download
    const [hoDl] = await Promise.all([
      page.waitForEvent('download', { timeout: 30000 }).catch(() => null),
      copyBtn.click()
    ]);
    if (hoDl) {
      const handoffZipPath = `${HANDOFF_DIR}/handoff-bundle.zip`;
      await hoDl.saveAs(handoffZipPath);
      spawnSync('unzip', ['-o', handoffZipPath, '-d', HANDOFF_DIR], { stdio: 'inherit' });
      console.error('[5] handoff bundle saved');
    }
  }
}

writeFileSync(`${HANDOFF_DIR}/.captured-at`, new Date().toISOString());
console.log(`[done] zipDownloaded=${zipDownloaded} dir=${HANDOFF_DIR}`);
await browser.close();
