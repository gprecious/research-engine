#!/usr/bin/env node
/**
 * Open Handoff modal, click "Download zip instead" checkbox,
 * see what UI changes / what button activates.
 */
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SLUG = process.argv[2];
const URL = process.argv[3];
const STATE_PATH = join(homedir(), '.config', 'research-engine', 'claude-design', 'storageState.json');
const HANDOFF_DIR = `research/${SLUG}/design/handoff`;
const SHOT_DIR = `${HANDOFF_DIR}/_handoff_flow`;
mkdirSync(SHOT_DIR, { recursive: true });

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ storageState: STATE_PATH, acceptDownloads: true });
const page = await ctx.newPage();

let i = 0;
const shot = async (name) => {
  i++;
  await page.screenshot({ path: `${SHOT_DIR}/${String(i).padStart(2,'0')}-${name}.png`, fullPage: false });
  console.error(`[shot] ${name}`);
};

console.error('[1] open design...');
await page.goto(URL, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(3000);
await shot('loaded');

console.error('[2] open Share → Handoff modal...');
await page.locator('button:has-text("Share")').first().click();
await page.waitForTimeout(800);
await page.locator('text=/Handoff to Claude Code/i').first().click();
await page.waitForTimeout(1500);
await shot('handoff-modal');

// Capture all interactive elements in the modal
const modalScope = page.locator('[role=dialog]:visible, .modal:visible, body').first();
console.error('[3] modal visible interactives:');
const btns = await page.locator('button:visible').allInnerTexts();
console.error('   buttons:', JSON.stringify(btns));
const inputs = await page.locator('input:visible').count();
console.error('   inputs:', inputs);
const tabs = await page.locator('[role=tab]:visible').allInnerTexts();
console.error('   tabs:', JSON.stringify(tabs));

// Try clicking the "Download zip instead" checkbox/label
console.error('[4] click "Download zip instead"...');
const dlZipCheckbox = page.locator('text=/Download zip instead/i').first();
await dlZipCheckbox.click({ force: true });
await page.waitForTimeout(1000);
await shot('after-dl-check');

// See if a download button now appears or modal changes
const btnsAfter = await page.locator('button:visible').allInnerTexts();
console.error('[5] buttons after toggle:', JSON.stringify(btnsAfter));

// Look for any download button (Download bundle, Get zip, etc)
const candidates = ['Download .zip', 'Download bundle', 'Download zip', 'Get bundle'];
for (const c of candidates) {
  const el = page.locator(`button:has-text("${c}")`).first();
  if (await el.isVisible({ timeout: 200 }).catch(() => false)) {
    console.error(`[6] trying click: "${c}"`);
    const [dl] = await Promise.all([
      page.waitForEvent('download', { timeout: 30000 }).catch(() => null),
      el.click()
    ]);
    if (dl) {
      const fn = await dl.suggestedFilename();
      const zp = `${HANDOFF_DIR}/handoff-bundle.zip`;
      await dl.saveAs(zp);
      const dest = `${HANDOFF_DIR}/full_bundle`;
      mkdirSync(dest, { recursive: true });
      spawnSync('unzip', ['-o', '-q', zp, '-d', dest], { stdio: 'inherit' });
      console.error(`[6] downloaded ${fn} → ${zp} → extracted to ${dest}`);
      const files = spawnSync('find', [dest, '-type', 'f'], { encoding: 'utf8' }).stdout;
      console.error('[6] files:', files);
      writeFileSync(`${HANDOFF_DIR}/_handoff-suggested-filename.txt`, fn);
      break;
    }
    console.error(`[6] no download event from "${c}"`);
  }
}

// Also try clicking "Copy command" — won't help us (clipboard not testable headless)
// but we can see the modal text content for the actual command
const cmdText = await page.locator('text=/Fetch this design file/i').first().textContent().catch(() => '');
if (cmdText) {
  console.error('[7] command text length:', cmdText.length);
  writeFileSync(`${HANDOFF_DIR}/_handoff_command.txt`, cmdText.trim());
}
// Capture the latest API URL
const bodyText = await page.locator('body').innerText();
const apiMatch = bodyText.match(/https:\/\/api\.anthropic\.com\/v1\/design\/h\/[A-Za-z0-9]+/);
if (apiMatch) {
  console.error('[8] api URL:', apiMatch[0]);
  writeFileSync(`${HANDOFF_DIR}/_handoff_api_url_latest.txt`, apiMatch[0]);
}

await shot('done');
await browser.close();
console.log('[done]');
