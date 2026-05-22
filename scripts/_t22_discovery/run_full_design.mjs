#!/usr/bin/env node
/**
 * Full end-to-end design generation:
 *   1. enter dashboard
 *   2. select "None" design system (NOT QPLACE)
 *   3. fill project name + High fidelity + Create
 *   4. send rich prompt that pre-decides all defaults to avoid timeout
 *   5. if "Questions timed out" chip appears, click it and send fallback
 *   6. wait for design to complete (up to 30 min)
 *   7. Share → Handoff to Claude Code → Download zip instead → save
 */
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SLUG = process.argv[2];
if (!SLUG) { console.error('usage: run_full_design.mjs <slug>'); process.exit(2); }

const STATE_PATH = join(homedir(), '.config', 'research-engine', 'claude-design', 'storageState.json');
const HANDOFF_DIR = `research/${SLUG}/design/handoff`;
const SHOT_DIR = `${HANDOFF_DIR}/_run2`;
rmSync(SHOT_DIR, { recursive: true, force: true });
mkdirSync(SHOT_DIR, { recursive: true });

const readme = readFileSync(`research/${SLUG}/README.md`, 'utf8').split('\n').slice(0, 200).join('\n');

const prompt = `다음 research 요약을 받아서 **인터랙티브 프로토타입** (Next.js/React 형태) 으로 만들어줘.

== research 요약 시작 ==
${readme}
== research 요약 끝 ==

## 명확화 없이 다음 사전 결정 그대로 진행해줘 (질문 던지지 마세요)

- **스타일**: modern minimal, 흰 배경에 단일 accent color (#3b82f6 또는 비슷한 saturated blue)
- **페이지**: (1) landing — hero + 핵심 문구 + Try free CTA, (2) /upload — 파일 업로드 input + Convert 버튼 + SVG preview 영역, (3) /health — 단순 OK 응답
- **타입스케일**: H1 56px / H2 28px / body 16px, font-family system-ui
- **CTA selector**: \`data-testid="cta-try"\` (랜딩의 Try free 버튼), \`data-testid="convert"\` (업로드 페이지의 변환 버튼), \`data-testid="svg-preview"\` (변환 결과 영역)
- **인터랙션**: 업로드 → Convert 클릭 → svg-preview 안에 mock SVG 즉시 표시 (실제 변환 알고리즘 불필요, mock 으로 OK)
- **컴포넌트 라이브러리**: 외부 의존성 없이 vanilla React + inline style
- **타겟**: 디자이너 + 마케터 (일러스트 / 로고 raster → SVG 변환 수요)

마지막에 \`Hand off to Claude Code\` 가능한 상태로 마무리해줘.`;

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ storageState: STATE_PATH, acceptDownloads: true });
const page = await ctx.newPage();

let shotIdx = 0;
const shot = async (name) => {
  shotIdx++;
  await page.screenshot({ path: `${SHOT_DIR}/${String(shotIdx).padStart(2, '0')}-${name}.png`, fullPage: false });
  console.error(`[shot] ${name} | url=${page.url()}`);
};

console.error('[1] enter dashboard...');
await page.goto('https://claude.ai/design', { waitUntil: 'domcontentloaded' });
await page.waitForSelector('input[placeholder*="Project name" i]', { timeout: 30000 });
await page.waitForTimeout(1500);
await shot('dashboard');

console.error('[2] fill project name...');
const nameInput = page.locator('input[placeholder*="Project name" i]').first();
await nameInput.fill(`${SLUG}-v2`);

console.error('[3] select "None" via native <select>...');
const selects = page.locator('select');
const cnt = await selects.count();
console.error(`[3] selects on page: ${cnt}`);
for (let i = 0; i < cnt; i++) {
  const opts = await selects.nth(i).locator('option').allInnerTexts();
  console.error(`[3]  select#${i} options: ${JSON.stringify(opts)}`);
}
// pick the design-system select (the one with an option containing 'None' and a Design System option)
let dsIdx = -1;
for (let i = 0; i < cnt; i++) {
  const opts = await selects.nth(i).locator('option').allInnerTexts();
  if (opts.some((t) => /none/i.test(t)) && opts.some((t) => /Design System|Default/i.test(t))) {
    dsIdx = i; break;
  }
}
if (dsIdx < 0) throw new Error('design-system select not found');
await selects.nth(dsIdx).selectOption({ label: 'None' });
await page.waitForTimeout(500);
await shot('ds-none-selected');

console.error('[4] click High fidelity...');
await page.locator('text=/^High[ \\u00a0]?fidelity$/i').first().click();
await page.waitForTimeout(300);

console.error('[5] click Create...');
await page.locator('button:has-text("Create")').first().click();

console.error('[6] wait for project workspace...');
await page.waitForURL(/\/design\/p\/.+/, { timeout: 30000 });
await page.waitForLoadState('domcontentloaded');
await page.waitForTimeout(3000);
const projectUrl = page.url();
console.error('[6] project URL:', projectUrl);
writeFileSync(`${HANDOFF_DIR}/_run2-project-url.txt`, projectUrl);
await shot('workspace');

console.error('[7] send rich prompt...');
const promptBox = page.locator('textarea, [role=textbox], [contenteditable=true]').first();
await promptBox.waitFor({ state: 'visible', timeout: 15000 });
await promptBox.fill(prompt);
await shot('prompt-typed');
const sendBtn = page.locator('button:has-text("Send"), button[aria-label*=send i]').first();
if (await sendBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
  await sendBtn.click();
} else {
  await promptBox.press('Enter');
}
await page.waitForTimeout(2000);
await shot('prompt-sent');

console.error('[8] poll for completion (max 35 min)...');
const MAX_S = 35 * 60;
const STEP_S = 20;
const steps = MAX_S / STEP_S;
let lastShotMin = -1;

for (let i = 0; i < steps; i++) {
  const elapsed = i * STEP_S;
  const elapsedMin = Math.floor(elapsed / 60);

  // 1) If "Questions timed out" chip is up, click it to proceed with defaults
  const timedOutChip = page.locator('text=/Questions timed out; go with defaults/i').first();
  if (await timedOutChip.isVisible({ timeout: 200 }).catch(() => false)) {
    console.error(`[${elapsed}s] timeout chip clicked`);
    await timedOutChip.click().catch(() => {});
    await page.waitForTimeout(2000);
  }

  // 2) If Claude is asking questions inline (other than the chip), send a fallback "use defaults" message
  const questionsLabel = page.locator('text=/Claude has some questions/i').first();
  if (await questionsLabel.isVisible({ timeout: 200 }).catch(() => false)) {
    // send a follow-up via prompt box
    const box = page.locator('textarea, [role=textbox], [contenteditable=true]').first();
    if (await box.isVisible({ timeout: 200 }).catch(() => false)) {
      const txt = await box.inputValue().catch(() => '');
      if (!txt) {
        console.error(`[${elapsed}s] Claude is asking — sending default-fallback message`);
        await box.fill('위의 사전 결정사항 그대로 진행하면 됩니다. 추가 질문 없이 디자인 완성해주세요.');
        const s = page.locator('button:has-text("Send")').first();
        if (await s.isVisible().catch(() => false)) await s.click();
        else await box.press('Enter');
        await page.waitForTimeout(3000);
      }
    }
  }

  // 3) Check whether Share menu's "Handoff to Claude Code" is now reachable (i.e., design ready enough)
  // Cheap probe: open Share, peek for the item, close.
  if (i > 0 && i % 6 === 0) {
    const shareBtn = page.locator('button:has-text("Share")').first();
    if (await shareBtn.isVisible({ timeout: 200 }).catch(() => false)) {
      await shareBtn.click({ trial: false }).catch(() => {});
      await page.waitForTimeout(700);
      const handoffItem = page.locator('text=/Handoff to Claude Code/i').first();
      const handoffReady = await handoffItem.isVisible({ timeout: 500 }).catch(() => false);
      // close menu by pressing escape
      await page.keyboard.press('Escape').catch(() => {});
      if (handoffReady) {
        // also check whether the design has more than the initial scaffolding
        // we want at least an 'index.html' or 'app/' in the file tree
        const fileEntry = page.locator('text=/index\\.html|page\\.tsx|home\\.tsx|app\\.css/i').first();
        const designHasFiles = await fileEntry.isVisible({ timeout: 500 }).catch(() => false);
        console.error(`[${elapsed}s] handoff visible=${handoffReady} designHasFiles=${designHasFiles}`);
        if (designHasFiles) {
          console.error(`[${elapsed}s] design appears ready — break poll`);
          break;
        }
      }
    }
  }

  if (elapsedMin !== lastShotMin && elapsedMin % 2 === 0) {
    lastShotMin = elapsedMin;
    await shot(`poll-${String(elapsedMin).padStart(2, '0')}min`);
  }
  await page.waitForTimeout(STEP_S * 1000);
}

console.error('[9] full-page snapshot...');
await page.screenshot({ path: `${HANDOFF_DIR}/design-screenshot.png`, fullPage: true });

console.error('[10] open Share → click Handoff to Claude Code → Download zip instead...');
const shareBtn = page.locator('button:has-text("Share")').first();
await shareBtn.click();
await page.waitForTimeout(800);
await shot('share-menu');

const handoffItem = page.locator('text=/Handoff to Claude Code/i').first();
if (!(await handoffItem.isVisible({ timeout: 3000 }).catch(() => false))) {
  console.error('[10-fail] Handoff item not visible. Falling back to Download project as .zip');
  const dlZip = page.locator('text=/Download project as .zip/i').first();
  if (await dlZip.isVisible({ timeout: 2000 }).catch(() => false)) {
    const [dl] = await Promise.all([
      page.waitForEvent('download', { timeout: 60000 }).catch(() => null),
      dlZip.click()
    ]);
    if (dl) {
      const zp = `${HANDOFF_DIR}/project-v2.zip`;
      await dl.saveAs(zp);
      spawnSync('unzip', ['-o', '-q', zp, '-d', HANDOFF_DIR], { stdio: 'inherit' });
      console.error('[10b] downloaded as project.zip and extracted');
    }
  }
  await browser.close();
  process.exit(0);
}

await handoffItem.click();
await page.waitForTimeout(2500);
await shot('handoff-modal');

// In the handoff modal, click "Download zip instead"
const dlInstead = page.locator('text=/Download zip instead/i').first();
if (await dlInstead.isVisible({ timeout: 3000 }).catch(() => false)) {
  const [dl] = await Promise.all([
    page.waitForEvent('download', { timeout: 60000 }).catch(() => null),
    dlInstead.click()
  ]);
  if (dl) {
    const zp = `${HANDOFF_DIR}/handoff-bundle-v2.zip`;
    await dl.saveAs(zp);
    spawnSync('unzip', ['-o', '-q', zp, '-d', HANDOFF_DIR], { stdio: 'inherit' });
    console.error('[11] handoff bundle downloaded & extracted');
  } else {
    console.error('[11-fail] no download event');
    await shot('handoff-after-click');
  }
} else {
  console.error('[10-fail] "Download zip instead" not visible');
  await shot('handoff-modal-no-dl');
}

await browser.close();
console.log('[done]');
