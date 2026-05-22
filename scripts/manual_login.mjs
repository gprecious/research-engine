#!/usr/bin/env node
/**
 * manual_login.mjs
 *   - Tailscale m4 의 Chrome 을 CDP 9222 로 띄움
 *   - 사용자에게 한글 안내 후 Enter 대기
 *   - chromium.connectOverCDP 로 attach, storageState 추출
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import readline from 'node:readline';
import { loadEnv, requireEnv } from '../lib/research_design_env.mjs';

const CACHE_DIR = join(homedir(), '.config', 'research-engine', 'claude-design');
const STATE_PATH = join(CACHE_DIR, 'storageState.json');
const META_PATH = join(CACHE_DIR, 'state.meta.json');
const CDP_PORT = 9222;

function prompt(msg) {
  return new Promise((res) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question(msg, (a) => { rl.close(); res(a); });
  });
}

async function main() {
  const env = loadEnv();
  const { M4_TAILSCALE_HOST, M4_TAILSCALE_USER } = requireEnv(['M4_TAILSCALE_HOST', 'M4_TAILSCALE_USER'], env);

  console.error(`\n[manual] Tailscale ${M4_TAILSCALE_USER}@${M4_TAILSCALE_HOST} 의 Chrome 을 CDP 모드로 띄웁니다…\n`);
  const sshArgs = [
    '-o', 'StrictHostKeyChecking=accept-new',
    '-L', `${CDP_PORT}:127.0.0.1:${CDP_PORT}`,
    `${M4_TAILSCALE_USER}@${M4_TAILSCALE_HOST}`,
    `open -a "Google Chrome" --args --remote-debugging-port=${CDP_PORT} --user-data-dir=/tmp/cdp-claude-design "https://claude.ai/login" && sleep 1800`
  ];
  const ssh = spawn('ssh', sshArgs, { stdio: ['ignore', 'inherit', 'inherit'] });

  await new Promise((r) => setTimeout(r, 5000));

  console.error('Mac m4 의 Chrome 에서 https://claude.ai/login → claude.ai/design 까지 로그인 완료한 뒤 여기서 Enter:');
  await prompt('');

  const { chromium } = await import('playwright');
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${CDP_PORT}`);
  const ctx = browser.contexts()[0];
  if (!ctx) {
    console.error('[manual] no browser context — Chrome 이 떠 있나요?');
    process.exit(1);
  }

  mkdirSync(CACHE_DIR, { recursive: true });
  await ctx.storageState({ path: STATE_PATH });
  writeFileSync(META_PATH, JSON.stringify({
    capturedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 14 * 86400 * 1000).toISOString(),
    method: 'manual-m4'
  }, null, 2));
  console.log(`[manual] storageState saved: ${STATE_PATH}`);

  ssh.kill();
  await browser.close();
}

main().catch((err) => { console.error('[manual] error:', err.message); process.exit(1); });
