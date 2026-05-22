#!/usr/bin/env node
/**
 * cloak_login.mjs
 *   - cloak-browser 로 headless 자격증명 로그인 시도
 *   - 성공 시 storageState 를 ~/.config/research-engine/claude-design/storageState.json 으로 저장
 *   - hCaptcha/Cloudflare 감지 시 즉시 exit 2 (fail-fast)
 */
import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';
import { execSync, spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { loadEnv, requireEnv } from '../lib/research_design_env.mjs';

const require = createRequire(import.meta.url);

const CACHE_DIR = join(homedir(), '.config', 'research-engine', 'claude-design');
const STATE_PATH = join(CACHE_DIR, 'storageState.json');
const META_PATH = join(CACHE_DIR, 'state.meta.json');

function ensureCloakBrowser() {
  try {
    require.resolve('cloak-browser');
  } catch {
    console.error('[cloak] cloak-browser not found — installing locally');
    const result = spawnSync('pnpm', ['add', '-D', 'cloak-browser', 'playwright'], { stdio: 'inherit' });
    if (result.status !== 0) {
      console.error('[cloak] cloak-browser install failed — continuing (may fail at import)');
    }
  }
}

async function main() {
  ensureCloakBrowser();
  const env = loadEnv();
  const { CLAUDE_LOGIN_EMAIL, CLAUDE_LOGIN_PW } = requireEnv(['CLAUDE_LOGIN_EMAIL', 'CLAUDE_LOGIN_PW'], env);

  const { stealth } = await import('cloak-browser');
  const { chromium } = await import('playwright');

  const browser = await chromium.launch({ headless: true });
  const context = await stealth(browser).newContext();
  const page = await context.newPage();

  await page.goto('https://claude.ai/login', { waitUntil: 'domcontentloaded' });
  if (await page.locator('iframe[src*="hcaptcha"], #challenge-stage').count()) {
    console.error('[cloak] captcha detected — fail-fast');
    await browser.close();
    process.exit(2);
  }

  await page.fill('input[type=email]', CLAUDE_LOGIN_EMAIL);
  await page.click('button[type=submit]');
  await page.waitForLoadState('domcontentloaded');

  if (await page.locator('iframe[src*="hcaptcha"], #challenge-stage').count()) {
    console.error('[cloak] captcha detected after email — fail-fast');
    await browser.close();
    process.exit(2);
  }

  await page.fill('input[type=password]', CLAUDE_LOGIN_PW);
  await page.click('button[type=submit]');

  await page.goto('https://claude.ai/design');
  const ok = await page
    .locator('[data-testid=user-menu], header img[alt*="avatar"], nav a[href*="design"]')
    .first()
    .waitFor({ timeout: 15000 })
    .then(() => true)
    .catch(() => false);

  if (!ok) {
    console.error('[cloak] login indicator not found — likely soft-blocked');
    await browser.close();
    process.exit(2);
  }

  mkdirSync(CACHE_DIR, { recursive: true });
  await context.storageState({ path: STATE_PATH });
  writeFileSync(META_PATH, JSON.stringify({
    capturedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 14 * 86400 * 1000).toISOString(),
    method: 'cloak'
  }, null, 2));
  await browser.close();
  console.log(`[cloak] storageState saved: ${STATE_PATH}`);
}

main().catch((err) => {
  console.error('[cloak] error:', err.message);
  process.exit(1);
});
