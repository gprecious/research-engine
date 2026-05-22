#!/usr/bin/env node
/**
 * Re-enter existing claude.ai/design project, send follow-up demanding
 * the missing page files (landing.jsx, upload.jsx, health.jsx, app.jsx),
 * wait for completion, capture new handoff API URL.
 *
 * Usage: force_finish_pages.mjs <slug> <project-url>
 */
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SLUG = process.argv[2];
const PROJECT_URL = process.argv[3];
if (!SLUG || !PROJECT_URL) {
  console.error('usage: force_finish_pages.mjs <slug> <project-url>');
  process.exit(2);
}

const STATE_PATH = join(homedir(), '.config', 'research-engine', 'claude-design', 'storageState.json');
const OUT_DIR = `research/${SLUG}/design/handoff/_force_finish`;
mkdirSync(OUT_DIR, { recursive: true });

const FOLLOWUP = `위 디자인이 미완성이다. index.html 이 landing.jsx, upload.jsx, health.jsx, app.jsx 4개 파일을 참조하지만 생성되지 않았다.

지금 즉시 다음 4개 파일을 생성해라. 명확화 질문 던지지 말 것. 이미 모든 결정사항은 첫 메시지에 포함되어 있다.

1. landing.jsx — Hero (H1 56px "Vectorize raster art", H2 28px subtitle, primary CTA button Try free with data-testid="cta-try" linking to #/upload). Use Nav and Footer from components.jsx. Inline style. Vanilla React. Background #ffffff, accent VECTRA_BLUE.

2. upload.jsx — Form with file <input type="file" accept="image/*">, Convert button data-testid="convert", svg-preview div data-testid="svg-preview". Clicking Convert renders a mock <svg> inside svg-preview. Use Nav from components.jsx. Inline style.

3. health.jsx — Single page that renders the literal text "OK" centered on screen. Minimal styling.

4. app.jsx — Hash-based router: #/ → Landing, #/upload → Upload, #/health → Health. Use ReactDOM.createRoot(document.getElementById('root')).render(<App />).

각 파일을 \`\`\`jsx 블록으로 출력. 질문 금지. 바로 코드만.`;

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ storageState: STATE_PATH });
const page = await ctx.newPage();

let shotNum = 0;
const shot = async (name) => {
  shotNum++;
  const path = `${OUT_DIR}/${String(shotNum).padStart(2, '0')}-${name}.png`;
  await page.screenshot({ path, fullPage: false }).catch(() => {});
  console.error(`[shot] ${name}`);
};

console.error('[1] open project URL...');
await page.goto(PROJECT_URL, { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForTimeout(4000);
await shot('loaded');

// Find chat input — typically a textarea or contenteditable div
console.error('[2] locate chat input...');
const inputCandidates = [
  'textarea[placeholder*="Reply" i]',
  'textarea[placeholder*="Ask" i]',
  'textarea[placeholder*="Message" i]',
  'textarea[placeholder*="Send" i]',
  '[contenteditable="true"]',
  'textarea',
];
let input = null;
for (const sel of inputCandidates) {
  const el = page.locator(sel).last();
  if (await el.isVisible({ timeout: 800 }).catch(() => false)) {
    console.error(`[2] using: ${sel}`);
    input = el;
    break;
  }
}
if (!input) {
  console.error('[FAIL] no input found');
  await shot('no-input');
  await browser.close();
  process.exit(3);
}

console.error('[3] type follow-up...');
await input.click();
await page.waitForTimeout(300);
await input.fill(FOLLOWUP);
await page.waitForTimeout(500);
await shot('typed');

console.error('[4] submit...');
// Try Enter first; if multi-line input, Ctrl+Enter
await page.keyboard.press('Enter').catch(() => {});
await page.waitForTimeout(2000);
await shot('submitted');

// Some chat UIs require Ctrl+Enter or send button
const sendBtn = page.locator(
  'button[aria-label*="Send" i], button[aria-label*="Submit" i], button:has(svg[class*="send" i])'
).first();
if (await sendBtn.isVisible({ timeout: 500 }).catch(() => false)) {
  console.error('[4b] also click send button...');
  await sendBtn.click().catch(() => {});
  await page.waitForTimeout(2000);
  await shot('after-send-btn');
}

console.error('[5] wait for design to finish (poll up to 25 min)...');
const MAX_MIN = 25;
const STEP_S = 20;
const steps = Math.floor((MAX_MIN * 60) / STEP_S);

async function isStillGenerating() {
  // Heuristic: presence of "Stop" button or any "generating" / "thinking" indicator
  const stopBtn = page.locator('button:has-text("Stop"), button[aria-label*="Stop" i]').first();
  if (await stopBtn.isVisible({ timeout: 200 }).catch(() => false)) return true;
  const gen = await page.locator('text=/Generating|Thinking|Drafting|Working on/i').count();
  return gen > 0;
}

let stableCount = 0;
for (let i = 0; i < steps; i++) {
  const stillGen = await isStillGenerating();
  if (!stillGen) {
    stableCount++;
    if (stableCount >= 3) {
      console.error(`[5] stable for ${stableCount * STEP_S}s — assume done`);
      break;
    }
  } else {
    stableCount = 0;
  }
  if (i % 3 === 0) {
    await shot(`poll-${String(i * STEP_S).padStart(4, '0')}s`);
  }
  await page.waitForTimeout(STEP_S * 1000);
}

console.error('[6] open Share menu...');
const shareBtn = page.locator('button:has-text("Share")').first();
await shareBtn.click({ timeout: 5000 });
await page.waitForTimeout(800);
await shot('share-open');

console.error('[7] click Handoff to Claude Code...');
await page.locator('text=/Handoff to Claude Code/i').first().click();
await page.waitForTimeout(2000);
await shot('handoff-modal');

// Capture handoff command text (which contains the API URL)
const body = await page.locator('body').innerText();
const urlMatch = body.match(/https:\/\/api\.anthropic\.com\/v1\/design\/h\/[A-Za-z0-9_-]+/);
if (urlMatch) {
  console.log(`HANDOFF_URL=${urlMatch[0]}`);
  writeFileSync(`${OUT_DIR}/handoff-url.txt`, urlMatch[0]);
} else {
  console.error('[7!] no API URL found in body');
  writeFileSync(`${OUT_DIR}/body-debug.txt`, body);
}

await shot('done');
await browser.close();
console.error('[done]');
