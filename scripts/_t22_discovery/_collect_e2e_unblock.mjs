#!/usr/bin/env node
import { chromium } from 'playwright';
import { homedir } from 'node:os';
import { join } from 'node:path';

const SLUG = process.argv[2];
const DESIGN_URL = process.argv[3];
const STATE_PATH = join(homedir(), '.config', 'research-engine', 'claude-design', 'storageState.json');
const HANDOFF_DIR = `research/${SLUG}/design/handoff`;

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ storageState: STATE_PATH, acceptDownloads: true });
const page = await ctx.newPage();

const shot = async (name) => {
  await page.screenshot({ path: `${HANDOFF_DIR}/_unblock-${name}.png`, fullPage: false });
  console.error(`[shot] ${name}`);
};

console.error('[1] resume...');
await page.goto(DESIGN_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
await page.waitForTimeout(2500);
await shot('01-state');

// click the "Questions timed out; go with defaults" chip
console.error('[2] try clicking the defaults chip...');
const defaultsChip = page.locator('text=/Questions timed out; go with defaults/i').first();
if (await defaultsChip.isVisible({ timeout: 3000 }).catch(() => false)) {
  await defaultsChip.click().catch(() => {});
  console.error('[2] chip clicked');
  await page.waitForTimeout(3000);
  await shot('02-after-chip');
} else {
  console.error('[2] chip not found — sending follow-up message instead');
  const promptBox = page.locator('textarea, [role=textbox], [contenteditable=true]').first();
  await promptBox.click().catch(() => {});
  await promptBox.fill('기본값으로 계속 진행해주세요. 디자인 완성 후 Hand off to Claude Code 가능한 상태로 마무리해주세요.');
  await shot('02b-typed');
  const sendBtn = page.locator('button:has-text("Send"), button[type="submit"], button[aria-label*=send i]').first();
  if (await sendBtn.count() > 0) await sendBtn.click().catch(() => {});
  else await promptBox.press('Enter');
  await page.waitForTimeout(3000);
  await shot('02c-sent');
}

// Now also try clicking Share to see hand off options
console.error('[3] check Share menu for Hand off option...');
const shareBtn = page.locator('button:has-text("Share")').first();
if (await shareBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
  await shareBtn.click().catch(() => {});
  await page.waitForTimeout(1500);
  await shot('03-share-open');
  // dump visible menu/dialog items
  const items = await page.locator('[role=menuitem], button:visible, [role=dialog] button:visible').allInnerTexts();
  console.error('[3] visible items in share UI:', items.slice(0, 30).join(' | '));
}

await browser.close();
console.log('[done] unblock attempted');
