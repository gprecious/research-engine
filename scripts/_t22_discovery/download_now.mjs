#!/usr/bin/env node
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SLUG = process.argv[2];
const URL = process.argv[3];
const STATE_PATH = join(homedir(), '.config', 'research-engine', 'claude-design', 'storageState.json');
const HANDOFF_DIR = `research/${SLUG}/design/handoff`;

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ storageState: STATE_PATH, acceptDownloads: true });
const page = await ctx.newPage();

console.error('[1] resume...');
await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
await page.waitForTimeout(3000);

await page.screenshot({ path: `${HANDOFF_DIR}/design-screenshot-v2.png`, fullPage: true });

console.error('[3] Share menu → Download project as .zip...');
await page.locator('button:has-text("Share")').first().click();
await page.waitForTimeout(800);
const dlZip = page.locator('text=/Download project as .zip/i').first();
const [zipDl] = await Promise.all([
  page.waitForEvent('download', { timeout: 60000 }).catch(() => null),
  dlZip.click()
]);
if (zipDl) {
  const zp = `${HANDOFF_DIR}/project-v2.zip`;
  await zipDl.saveAs(zp);
  const outDir = `${HANDOFF_DIR}/v2`;
  mkdirSync(outDir, { recursive: true });
  spawnSync('unzip', ['-o', '-q', zp, '-d', outDir], { stdio: 'inherit' });
  console.error('[3] saved to', zp);
}

await page.keyboard.press('Escape').catch(() => {});
await page.waitForTimeout(500);
await page.locator('button:has-text("Share")').first().click();
await page.waitForTimeout(800);
const handoff = page.locator('text=/Handoff to Claude Code/i').first();
if (await handoff.isVisible({ timeout: 1500 }).catch(() => false)) {
  await handoff.click();
  await page.waitForTimeout(1800);
  const bodyText = await page.locator('body').innerText();
  const m = bodyText.match(/https:\/\/api\.anthropic\.com\/v1\/design\/h\/[A-Za-z0-9]+/);
  if (m) {
    writeFileSync(`${HANDOFF_DIR}/handoff-api-url-v2.txt`, m[0] + '\n');
    console.error('[4] handoff URL:', m[0]);
  }
}

writeFileSync(`${HANDOFF_DIR}/.captured-at-v2`, new Date().toISOString());
await browser.close();
console.log('[done]');
