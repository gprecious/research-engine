#!/usr/bin/env node
/**
 * Quick: open project URL, click Share → Handoff, capture URL.
 */
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SLUG = process.argv[2];
const PROJECT_URL = process.argv[3];

const STATE_PATH = join(homedir(), '.config', 'research-engine', 'claude-design', 'storageState.json');
const OUT_DIR = `research/${SLUG}/design/handoff/_grab`;
mkdirSync(OUT_DIR, { recursive: true });

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ storageState: STATE_PATH });
const page = await ctx.newPage();

let n = 0;
const shot = async (name) => {
  n++;
  await page.screenshot({ path: `${OUT_DIR}/${String(n).padStart(2, '0')}-${name}.png`, fullPage: false }).catch(() => {});
};

console.error('[1] open...');
await page.goto(PROJECT_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.locator('button:has-text("Share")').first().waitFor({ state: 'visible', timeout: 90000 });
await page.waitForTimeout(3000);
await shot('loaded');

console.error('[2] click Share...');
await page.locator('button:has-text("Share")').first().click();
await page.waitForTimeout(800);
await shot('share');

console.error('[3] click Handoff...');
// Find clickable parent of "Handoff to Claude Code" strong element
const handoffItem = page.locator(
  '[role=menuitem]:has-text("Handoff to Claude Code"), button:has-text("Handoff to Claude Code"), a:has-text("Handoff to Claude Code")'
).first();
await handoffItem.click({ force: true });
await page.waitForTimeout(3000);
await shot('handoff');

const body = await page.locator('body').innerText();
const m = body.match(/https:\/\/api\.anthropic\.com\/v1\/design\/h\/[A-Za-z0-9_-]+/);
if (m) {
  console.log(`HANDOFF_URL=${m[0]}`);
  writeFileSync(`${OUT_DIR}/handoff-url.txt`, m[0]);
} else {
  console.error('[!] no URL');
  writeFileSync(`${OUT_DIR}/body.txt`, body);
}

await shot('done');
await browser.close();
