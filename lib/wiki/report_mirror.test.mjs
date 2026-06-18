import { describe, it, expect, beforeEach } from 'vitest';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { mirrorReport, reportFilename, sanitizeFilename } from './report_mirror.mjs';
import { parsePage } from './frontmatter.mjs';

let vault, research;
beforeEach(async () => {
  vault = await fs.mkdtemp(path.join(os.tmpdir(), 'vault-'));
  research = await fs.mkdtemp(path.join(os.tmpdir(), 'research-'));
});

const README = `---
title: "qplace herdr timeout — 정찰"
slug: 2026-05-23-herdr-tailscale-timeout
date: 2026-05-23
---

## TL;DR
본문 그대로.
`;

async function writeReadme(text = README) {
  const dir = path.join(research, 'session');
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(path.join(dir, 'README.md'), text);
  return dir;
}

describe('sanitizeFilename', () => {
  it('strips filesystem-unsafe chars but keeps Korean', () => {
    expect(sanitizeFilename('a/b:c*d?"한글"')).toBe('a b c d 한글');
  });
});

describe('reportFilename', () => {
  it('prefixes date and keeps a readable Korean title', () => {
    expect(reportFilename('RAG는 죽었는가', '2026-06-12')).toBe('2026-06-12 RAG는 죽었는가.md');
  });
  it('omits prefix when date is malformed', () => {
    expect(reportFilename('제목', 'nope')).toBe('제목.md');
  });
});

describe('mirrorReport', () => {
  it('writes verbatim body + augmented frontmatter into reports/', async () => {
    const dir = await writeReadme();
    const r = await mirrorReport({ vaultDir: vault, researchDir: dir, date: '2026-06-18' });
    expect(r.file).toBe('reports/2026-05-23 qplace herdr timeout — 정찰.md');
    expect(r.action).toBe('created');
    const written = await fs.readFile(path.join(vault, r.file), 'utf8');
    const { frontmatter, body } = parsePage(written);
    expect(frontmatter.report_slug).toBe('2026-05-23-herdr-tailscale-timeout');
    expect(frontmatter.source).toBe('research/2026-05-23-herdr-tailscale-timeout');
    expect(frontmatter.tags).toEqual(expect.arrayContaining(['ai-generated', 'research-report']));
    expect(frontmatter.title).toBe('qplace herdr timeout — 정찰'); // 원본 보존
    expect(body).toContain('본문 그대로.');
  });

  it('is idempotent and removes the stale file on title change', async () => {
    const dir = await writeReadme();
    await mirrorReport({ vaultDir: vault, researchDir: dir, date: '2026-06-18' });
    await fs.writeFile(path.join(dir, 'README.md'), README.replace('정찰', '재정찰'));
    const r2 = await mirrorReport({ vaultDir: vault, researchDir: dir, date: '2026-06-19' });
    expect(r2.action).toBe('created'); // 새 파일명이라 created, 단 stale 제거됨
    const files = (await fs.readdir(path.join(vault, 'reports'))).filter((f) => f.endsWith('.md'));
    expect(files).toHaveLength(1);
    expect(files[0]).toContain('재정찰');
  });
});
