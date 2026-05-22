#!/usr/bin/env node
/**
 * Refined attempt — wait properly for hydration, send simpler message,
 * wait for all 4 page files to appear, capture handoff URL.
 */
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SLUG = process.argv[2];
const PROJECT_URL = process.argv[3];
if (!SLUG || !PROJECT_URL) {
  console.error('usage: finish_v2.mjs <slug> <project-url>');
  process.exit(2);
}

const STATE_PATH = join(homedir(), '.config', 'research-engine', 'claude-design', 'storageState.json');
const OUT_DIR = `research/${SLUG}/design/handoff/_finish_v2`;
mkdirSync(OUT_DIR, { recursive: true });

const MSG = `landing.jsx, upload.jsx, health.jsx, app.jsx 4개를 지금 생성. PricingCard 같은 새 컴포넌트 추가 금지. 첫 메시지의 사양 그대로:

- landing.jsx: Hero 페이지. H1 56px "Vectorize raster art", subtitle, Try free CTA data-testid="cta-try" → #/upload. Nav + Footer use.
- upload.jsx: <input type="file">, Convert button data-testid="convert", svg-preview div data-testid="svg-preview". Convert 클릭 → mock SVG render.
- health.jsx: "OK" 텍스트만 가운데.
- app.jsx: hash router (#/, #/upload, #/health) + ReactDOM.createRoot render.

각 파일 ` + '```' + `jsx 코드만 출력. 질문/설명 금지.`;

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

console.error('[1] navigate...');
await page.goto(PROJECT_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });

console.error('[2] wait for hydration — Share button visible (up to 90s)...');
await page.locator('button:has-text("Share")').first().waitFor({ state: 'visible', timeout: 90000 });
await page.waitForTimeout(2000);
await shot('hydrated');

// Check current files in panel
async function presentFiles() {
  const present = new Set();
  for (const fn of REQUIRED) {
    if (await page.locator(`text="${fn}"`).count().catch(() => 0) > 0) present.add(fn);
  }
  return present;
}

let present = await presentFiles();
console.error(`[2.5] initial files: ${[...present].join(',') || '(none)'}`);

if (present.size === REQUIRED.length) {
  console.error('[!] all files already present, skip send');
} else {
  console.error('[3] find chat input...');
  const inputSelectors = [
    'div[contenteditable="true"]',
    'textarea[placeholder*="Describe" i]',
    'textarea[placeholder*="Reply" i]',
    'textarea',
  ];
  let input = null;
  for (const sel of inputSelectors) {
    const el = page.locator(sel).last();
    if (await el.isVisible({ timeout: 2000 }).catch(() => false)) {
      input = el;
      console.error(`[3] input: ${sel}`);
      break;
    }
  }
  if (!input) {
    console.error('[FAIL] no input');
    await shot('no-input');
    await browser.close();
    process.exit(3);
  }

  await input.click();
  await page.waitForTimeout(500);
  // For contenteditable, use keyboard typing
  await page.keyboard.type(MSG, { delay: 5 });
  await page.waitForTimeout(800);
  await shot('typed');

  console.error('[4] press Ctrl+Enter and find Send btn...');
  // Try multiple send approaches
  const sendBtn = page.locator(
    'button[aria-label*="Send" i], button[aria-label*="Submit" i]'
  ).first();
  if (await sendBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
    await sendBtn.click().catch(() => {});
    console.error('[4] clicked Send button');
  } else {
    await page.keyboard.press('Enter');
    console.error('[4] pressed Enter');
  }
  await page.waitForTimeout(3000);
  await shot('submitted');
}

console.error('[5] poll for all 4 files (up to 25 min)...');
const MAX_MIN = 25;
const STEP_S = 20;
const steps = Math.floor((MAX_MIN * 60) / STEP_S);
let allPresent = false;
for (let i = 0; i < steps; i++) {
  present = await presentFiles();
  const elapsed = i * STEP_S;
  console.error(`[poll] ${elapsed}s | files: ${[...present].sort().join(',') || '(none)'} (${present.size}/${REQUIRED.length})`);
  if (present.size === REQUIRED.length) {
    // verify stability for another cycle
    await page.waitForTimeout(STEP_S * 1000);
    const recheck = await presentFiles();
    if (recheck.size === REQUIRED.length) {
      allPresent = true;
      console.error('[5!] all 4 files present');
      await shot('all-present');
      break;
    }
  }
  if (i % 3 === 0) await shot(`poll-${String(elapsed).padStart(4, '0')}s`);
  await page.waitForTimeout(STEP_S * 1000);
}

if (!allPresent) {
  console.error('[!] timed out without all 4 files');
}

console.error('[6] open Share + Handoff...');
await page.locator('button:has-text("Share")').first().click();
await page.waitForTimeout(800);
await shot('share');
await page.locator('text=/Handoff to Claude Code/i').first().click();
await page.waitForTimeout(3000);
await shot('handoff');

const body = await page.locator('body').innerText();
const urlMatch = body.match(/https:\/\/api\.anthropic\.com\/v1\/design\/h\/[A-Za-z0-9_-]+/);
if (urlMatch) {
  console.log(`HANDOFF_URL=${urlMatch[0]}`);
  writeFileSync(`${OUT_DIR}/handoff-url.txt`, urlMatch[0]);
} else {
  writeFileSync(`${OUT_DIR}/body.txt`, body);
  console.error('[!] no URL found, body saved');
}

await shot('done');
await browser.close();
console.error('[done]');
