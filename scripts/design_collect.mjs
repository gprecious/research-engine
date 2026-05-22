#!/usr/bin/env node
/**
 * design_collect.mjs <slug> [--from-url <handoff-api-url>]
 *
 * Two modes:
 *
 * 1) Auto (default): try storageState → cloak_login → manual_login chain to
 *    drive claude.ai/design directly. If every fallback fails, print a ready-
 *    to-paste prompt to stdout and exit non-zero — DO NOT attempt any further
 *    workaround. The user pastes the prompt into claude.ai/design themselves
 *    and re-runs with --from-url <handoff>.
 *
 * 2) From-URL: `--from-url https://api.anthropic.com/v1/design/h/<id>` fetches
 *    the bundle directly (no browser needed) and unpacks it into
 *    research/<slug>/design/handoff/.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync, createWriteStream } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pipeline } from 'node:stream/promises';

const CACHE_DIR = join(homedir(), '.config', 'research-engine', 'claude-design');
const STATE_PATH = join(CACHE_DIR, 'storageState.json');
const META_PATH = join(CACHE_DIR, 'state.meta.json');

const args = process.argv.slice(2);
const slug = args[0];
const fromUrlIdx = args.indexOf('--from-url');
const fromUrl = fromUrlIdx >= 0 ? args[fromUrlIdx + 1] : null;

if (!slug || slug.startsWith('--')) {
  console.error('usage: design_collect.mjs <slug> [--from-url <handoff-api-url>]');
  process.exit(2);
}

const handoffDir = `research/${slug}/design/handoff`;
mkdirSync(handoffDir, { recursive: true });

function buildPrompt(slug, readme) {
  const trimmed = readme.split('\n').slice(0, 200).join('\n');
  return `다음 research 결과를 인터랙티브 프로토타입(원페이지 또는 멀티페이지)으로 만들어줘. 핵심 메시지와 CTA 가 분명하게, 실서비스 수준의 디자인 시스템(색·타이포·컴포넌트)을 일관되게 적용. 마지막에 'Hand off to Claude Code' 가능한 상태로 마무리.

slug: ${slug}

${trimmed}`;
}

function printManualPromptAndExit(slug, readme, reason) {
  const prompt = buildPrompt(slug, readme);
  const block = [
    '',
    '════════════════════════════════════════════════════════════════════',
    '  claude.ai/design 자동 접근 실패 — 사용자 수동 진행 필요',
    '════════════════════════════════════════════════════════════════════',
    `사유: ${reason}`,
    '',
    '── 1단계 — 브라우저에서 직접 진행 ───────────────────────────────────',
    '   1. https://claude.ai/design 접속 (로그인 필요시 직접 로그인)',
    '   2. "New design" 클릭',
    '   3. Design system: "None" 선택 (또는 원하는 것)',
    '   4. 아래 프롬프트 전체를 메시지 박스에 붙여넣고 전송',
    '   5. 디자인 완성 대기 → 우상단 "Share" → "Handoff to Claude Code…" 클릭',
    '   6. 모달에 표시된 명령 안의 URL 복사:',
    '         Fetch this design file, … https://api.anthropic.com/v1/design/h/XXXX',
    '                                  ↑ 이 URL 만 복사',
    '',
    '── 2단계 — 그 URL 로 파이프라인 재개 ────────────────────────────────',
    `   node scripts/design_collect.mjs ${slug} --from-url <URL>`,
    '',
    '── 붙여넣을 프롬프트 본문 (— 아래 줄부터 다음 — 까지) ───────────────',
    '—',
    prompt,
    '—',
    '════════════════════════════════════════════════════════════════════',
    '',
  ].join('\n');
  process.stderr.write(block);
  // exit non-zero so callers know automation didn't complete; prompt is on stderr.
  process.exit(11);
}

async function fetchFromUrl(url) {
  console.error(`[collect] --from-url mode: fetching ${url}`);
  const res = await fetch(url);
  if (!res.ok) {
    console.error(`[collect] HTTP ${res.status} from handoff URL`);
    process.exit(1);
  }
  const gzPath = `${handoffDir}/bundle.tar.gz`;
  await pipeline(res.body, createWriteStream(gzPath));
  const tarPath = `${handoffDir}/bundle.tar`;
  spawnSync('gunzip', ['-fk', gzPath], { stdio: 'inherit' });
  // gunzip -k keeps .gz and writes bundle.tar
  const r = spawnSync('tar', ['-xf', tarPath, '-C', handoffDir], { stdio: 'inherit' });
  if (r.status !== 0) {
    console.error('[collect] tar extract failed');
    process.exit(1);
  }
  writeFileSync(`${handoffDir}/.captured-at`, new Date().toISOString());
  writeFileSync(`${handoffDir}/handoff-api-url.txt`, url);
  console.log(`[collect] handoff saved via --from-url: ${handoffDir}`);
}

function stateValid() {
  if (!existsSync(STATE_PATH) || !existsSync(META_PATH)) return false;
  try {
    const meta = JSON.parse(readFileSync(META_PATH, 'utf8'));
    return new Date(meta.expiresAt) > new Date();
  } catch {
    return false;
  }
}

function runLogin(script) {
  const r = spawnSync('node', [`scripts/${script}.mjs`], { stdio: 'inherit' });
  return r.status === 0;
}

async function ensureLoginOrFallback(readme) {
  if (stateValid()) {
    console.error('[collect] storageState valid — reusing');
    return;
  }
  console.error('[collect] storageState missing/expired — trying cloak_login');
  if (runLogin('cloak_login')) return;
  console.error('[collect] cloak_login failed — falling back to manual_login (Tailscale m4)');
  if (runLogin('manual_login')) return;
  printManualPromptAndExit(slug, readme, '로그인 자동화 (cloak_login + manual_login) 모두 실패');
}

async function collectAuto(readme) {
  const { chromium } = await import('playwright');
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ storageState: STATE_PATH, acceptDownloads: true });
  const page = await ctx.newPage();

  await page.goto('https://claude.ai/design', { waitUntil: 'domcontentloaded' });
  const loggedIn = await page.locator('[data-testid=user-menu], header img[alt*="avatar"], nav a[href*="design"]').first()
    .waitFor({ timeout: 15000 }).then(() => true).catch(() => false);
  if (!loggedIn) {
    await browser.close();
    printManualPromptAndExit(slug, readme, 'design 페이지 진입 실패 (storageState 무효 가능)');
  }

  const newDesignClicked = await page.locator('button:has-text("New design"), [data-testid=new-design]').first()
    .click({ timeout: 10000 }).then(() => true).catch(() => false);
  if (!newDesignClicked) {
    await browser.close();
    printManualPromptAndExit(slug, readme, '"New design" 버튼 클릭 실패');
  }

  const promptBox = page.locator('textarea, [role=textbox]').first();
  const filled = await promptBox.fill(buildPrompt(slug, readme)).then(() => true).catch(() => false);
  if (!filled) {
    await browser.close();
    printManualPromptAndExit(slug, readme, '프롬프트 입력 실패');
  }

  const submitted = await page.locator('button[type=submit], [data-testid=submit-prompt]').first()
    .click({ timeout: 5000 }).then(() => true).catch(() => false);
  if (!submitted) {
    await browser.close();
    printManualPromptAndExit(slug, readme, '프롬프트 제출 실패');
  }

  console.error('[collect] 디자인 생성 대기 중 (최대 5분)…');
  const handoffReady = await page.locator('button:has-text("Hand off to Claude Code"), [data-testid=handoff]')
    .first().waitFor({ timeout: 300000 }).then(() => true).catch(() => false);
  if (!handoffReady) {
    await browser.close();
    printManualPromptAndExit(slug, readme, '디자인 생성 5분 초과 또는 Handoff 버튼 미출현');
  }

  await page.screenshot({ path: `${handoffDir}/design-screenshot.png`, fullPage: true });

  let download = null;
  try {
    [download] = await Promise.all([
      page.waitForEvent('download', { timeout: 120000 }),
      page.locator('button:has-text("Hand off to Claude Code"), [data-testid=handoff]').first().click(),
    ]);
  } catch {
    await browser.close();
    printManualPromptAndExit(slug, readme, 'Handoff ZIP 다운로드 실패');
  }

  const zipPath = `${handoffDir}/bundle.zip`;
  await download.saveAs(zipPath);
  spawnSync('unzip', ['-o', zipPath, '-d', handoffDir], { stdio: 'inherit' });
  writeFileSync(`${handoffDir}/.captured-at`, new Date().toISOString());

  await browser.close();
  console.log(`[collect] handoff saved: ${handoffDir}`);
}

if (fromUrl) {
  await fetchFromUrl(fromUrl);
} else {
  const readmePath = `research/${slug}/README.md`;
  if (!existsSync(readmePath)) {
    console.error(`[collect] missing ${readmePath}`);
    process.exit(1);
  }
  const readme = readFileSync(readmePath, 'utf8');
  await ensureLoginOrFallback(readme);
  await collectAuto(readme);
}
