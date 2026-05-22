#!/usr/bin/env node
/**
 * Navigate to existing design project, wait until ALL 4 page files
 * (landing.jsx, upload.jsx, health.jsx, app.jsx) appear in the right-side file panel.
 * Then capture handoff API URL.
 *
 * Usage: wait_for_pages.mjs <slug> <project-url>
 */
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SLUG = process.argv[2];
const PROJECT_URL = process.argv[3];
if (!SLUG || !PROJECT_URL) {
  console.error('usage: wait_for_pages.mjs <slug> <project-url>');
  process.exit(2);
}

const STATE_PATH = join(homedir(), '.config', 'research-engine', 'claude-design', 'storageState.json');
const OUT_DIR = `research/${SLUG}/design/handoff/_wait_pages`;
mkdirSync(OUT_DIR, { recursive: true });

const REQUIRED = ['landing.jsx', 'upload.jsx', 'health.jsx', 'app.jsx'];

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ storageState: STATE_PATH });
const page = await ctx.newPage();

let shotNum = 0;
const shot = async (name) => {
  shotNum++;
  await page.screenshot({ path: `${OUT_DIR}/${String(shotNum).padStart(3, '0')}-${name}.png`, fullPage: false }).catch(() => {});
  console.error(`[shot] ${name}`);
};

console.error('[1] open project URL...');
await page.goto(PROJECT_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForTimeout(5000);
await shot('loaded');

const MAX_MIN = 30;
const STEP_S = 25;
const steps = Math.floor((MAX_MIN * 60) / STEP_S);

async function presentFiles() {
  // The file panel lists filenames in elements with the name text
  const present = new Set();
  for (const fn of REQUIRED) {
    const cnt = await page.locator(`text="${fn}"`).count().catch(() => 0);
    if (cnt > 0) present.add(fn);
  }
  return present;
}

async function isWorking() {
  // Various indicators
  const indicators = [
    'button:has-text("Stop")',
    'button[aria-label*="Stop" i]',
    'text=/Working/i',
    'text=/Listing/i',
    'text=/Reading/i',
    'text=/Writing/i',
    'text=/Creating/i',
    'text=/Updating/i',
    'text=/Drafting/i',
    'text=/Generating/i',
    'text=/Thinking/i',
    'text=/Analyzing/i',
  ];
  for (const sel of indicators) {
    if (await page.locator(sel).count().catch(() => 0) > 0) return sel;
  }
  return null;
}

console.error(`[2] poll until all ${REQUIRED.length} required files appear...`);
let allPresent = false;
for (let i = 0; i < steps; i++) {
  const present = await presentFiles();
  const working = await isWorking();
  const elapsed = i * STEP_S;
  console.error(`[poll] ${elapsed}s elapsed | files: ${[...present].join(',') || '(none)'} | working: ${working || 'no'}`);
  if (present.size === REQUIRED.length) {
    // double check: still wait one cycle if working indicator visible (might still be writing)
    if (!working) {
      allPresent = true;
      break;
    }
  }
  if (i % 4 === 0) await shot(`poll-${String(elapsed).padStart(4, '0')}s`);
  await page.waitForTimeout(STEP_S * 1000);
}
await shot('after-poll');

if (!allPresent) {
  console.error(`[!] timed out — required files not all present. Capturing handoff anyway.`);
}

console.error('[3] open Share menu...');
const shareBtn = page.locator('button:has-text("Share")').first();
await shareBtn.click({ timeout: 5000 });
await page.waitForTimeout(800);
await shot('share-open');

console.error('[4] click Handoff to Claude Code...');
await page.locator('text=/Handoff to Claude Code/i').first().click();
await page.waitForTimeout(2500);
await shot('handoff-modal');

const body = await page.locator('body').innerText();
const urlMatch = body.match(/https:\/\/api\.anthropic\.com\/v1\/design\/h\/[A-Za-z0-9_-]+/);
if (urlMatch) {
  console.log(`HANDOFF_URL=${urlMatch[0]}`);
  writeFileSync(`${OUT_DIR}/handoff-url.txt`, urlMatch[0]);
} else {
  console.error('[!] no API URL found');
  writeFileSync(`${OUT_DIR}/body-debug.txt`, body);
}

await shot('done');
await browser.close();
console.error('[done]');
