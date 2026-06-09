import { describe, it, expect, beforeEach } from 'vitest';
import { execFile } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { promote } from './promote.mjs';
import { parsePage, serializePage } from './frontmatter.mjs';

const execFileAsync = promisify(execFile);

let vault;
beforeEach(async () => {
  vault = await fs.mkdtemp(path.join(os.tmpdir(), 'wiki-promote-'));
});

async function writePage(rel, frontmatter, body = '## TL;DR\n요약\n\n## 출처별 관점\n\n### research/a\n- 주장 [1]\n') {
  const abs = path.join(vault, rel);
  await fs.mkdir(path.dirname(abs), { recursive: true });
  await fs.writeFile(abs, serializePage({ frontmatter, body }));
}

const draftFm = {
  type: 'concept',
  title: 'Draft A',
  slug: 'draft-a',
  aliases: [],
  sources: ['research/a'],
  related: [],
  tags: ['ai-generated', 'llm-wiki', 'concept'],
  confidence: 'medium',
  created: '2026-06-08',
  updated: '2026-06-08',
};

const read = (rel) => fs.readFile(path.join(vault, rel), 'utf8');

describe('promote', () => {
  it('draft 1개를 live 로 이동하고 index/log/change_log 를 갱신한다', async () => {
    await writePage('_drafts/concepts/draft-a.md', draftFm);

    const result = await promote({ vaultDir: vault, slugs: ['draft-a'], date: '2026-06-09' });

    expect(result.promoted).toEqual(['concepts/draft-a.md']);
    expect(result.skipped).toEqual([]);
    await expect(read('concepts/draft-a.md')).resolves.toMatch(/slug: draft-a/);
    await expect(read('_drafts/concepts/draft-a.md')).rejects.toThrow();
    expect(await read('index.md')).toMatch(/\[\[draft-a\]\]/);
    expect(await read('log.md')).toMatch(/promote \| draft-a/);
    expect(await read('change_log.md')).toMatch(/promote/);
  });

  it('재호출은 멱등: promoted=0, skipped 에 slug 기록', async () => {
    await writePage('_drafts/concepts/draft-a.md', draftFm);
    await promote({ vaultDir: vault, slugs: ['draft-a'], date: '2026-06-09' });

    const second = await promote({ vaultDir: vault, slugs: ['draft-a'], date: '2026-06-09' });

    expect(second.promoted).toEqual([]);
    expect(second.skipped).toEqual([{ slug: 'draft-a', reason: 'already-live' }]);
  });

  it('all=true 은 모든 draft 페이지를 승격한다', async () => {
    await writePage('_drafts/concepts/draft-a.md', draftFm);
    await writePage('_drafts/entities/entity-b.md', {
      ...draftFm,
      type: 'entity',
      title: 'Entity B',
      slug: 'entity-b',
      tags: ['ai-generated', 'llm-wiki', 'entity'],
      sources: ['research/b'],
    }, '## TL;DR\n요약\n\n## 출처별 관점\n\n### research/b\n- 주장 [1]\n');

    const result = await promote({ vaultDir: vault, all: true, date: '2026-06-09' });

    expect(result.promoted.sort()).toEqual(['concepts/draft-a.md', 'entities/entity-b.md']);
  });

  it('기존 live 페이지가 있으면 sources/sections 를 merge 하고 draft 를 제거한다', async () => {
    await writePage('concepts/draft-a.md', {
      ...draftFm,
      sources: ['research/old'],
      updated: '2026-06-01',
    }, '## TL;DR\n기존\n\n## 출처별 관점\n\n### research/old\n- 기존 [1]\n');
    await writePage('_drafts/concepts/draft-a.md', {
      ...draftFm,
      sources: ['research/a'],
    });

    const result = await promote({ vaultDir: vault, slugs: ['draft-a'], date: '2026-06-09' });

    expect(result.promoted).toEqual(['concepts/draft-a.md']);
    const { frontmatter, body } = parsePage(await read('concepts/draft-a.md'));
    expect(frontmatter.sources).toEqual(['research/old', 'research/a']);
    expect(frontmatter.updated).toBe('2026-06-09');
    expect(body).toMatch(/### research\/old/);
    expect(body).toMatch(/### research\/a/);
    await expect(read('_drafts/concepts/draft-a.md')).rejects.toThrow();
  });

  it('잘못된 slug 는 경로탈출 없이 거부한다', async () => {
    await expect(promote({ vaultDir: vault, slugs: ['../../outside'], date: '2026-06-09' }))
      .rejects.toThrow(/slug/);
  });
});

describe('promote CLI', () => {
  it('--all JSON 결과를 출력한다', async () => {
    await writePage('_drafts/concepts/draft-a.md', draftFm);
    const { stdout } = await execFileAsync(process.execPath, [
      path.join(process.cwd(), 'lib/wiki/promote.mjs'),
      '--vault', vault,
      '--all',
      '--date', '2026-06-09',
    ]);
    expect(JSON.parse(stdout).promoted).toEqual(['concepts/draft-a.md']);
  });
});
