import { describe, it, expect, beforeEach } from 'vitest';
import { execFile } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { classify, applyTier } from './librarian.mjs';
import { parsePage, serializePage } from './frontmatter.mjs';

const execFileAsync = promisify(execFile);

let vault;
beforeEach(async () => {
  vault = await fs.mkdtemp(path.join(os.tmpdir(), 'wiki-lib-'));
});

async function writePage(rel, frontmatter, body = '## 출처별 관점\n### research/a\n- 주장 [1]\n') {
  const abs = path.join(vault, rel);
  await fs.mkdir(path.dirname(abs), { recursive: true });
  await fs.writeFile(abs, serializePage({ frontmatter, body }));
}

const read = (rel) => fs.readFile(path.join(vault, rel), 'utf8');

describe('classify', () => {
  it('auto/draft findings 를 분리한다', () => {
    const out = classify([
      { rule: 'broken-link', slug: 'a' },
      { rule: 'duplicate-name', slug: 'b' },
      { rule: 'stale', slug: 'c' },
      { rule: 'tag-fix', slug: 'd' },
      { rule: 'raw-coverage', slug: 'research/x' },
      { rule: 'new-page', slug: 'n' },
      { rule: 'new-link', slug: 'l' },
      { rule: 'synthesis', slug: 's' },
      { rule: 'schema', slug: 'schema' },
    ]);
    expect(out.auto.map(f => f.rule)).toEqual(['broken-link', 'duplicate-name', 'stale', 'tag-fix', 'raw-coverage']);
    expect(out.draft.map(f => f.rule)).toEqual(['new-page', 'new-link', 'synthesis', 'schema']);
  });
});

describe('applyTier', () => {
  it('auto: broken-link 제거, tag 보정, stale 표시, change_log 기록', async () => {
    await writePage('concepts/a.md', {
      type: 'concept',
      title: 'A',
      slug: 'a',
      sources: ['research/a'],
      related: ['[[ghost]]', '[[b]]'],
      created: '2026-01-01',
      updated: '2026-01-01',
    });

    const result = await applyTier({
      vaultDir: vault,
      tier: 'auto',
      budget: 10,
      plan: {
        date: '2026-06-09',
        auto: [
          { rule: 'broken-link', slug: 'a', target: 'ghost' },
          { rule: 'tag-fix', slug: 'a' },
          { rule: 'stale', slug: 'a' },
        ],
      },
    });

    expect(result.applied).toHaveLength(3);
    const { frontmatter } = parsePage(await read('concepts/a.md'));
    expect(frontmatter.related).toEqual(['[[b]]']);
    expect(frontmatter.tags).toEqual(expect.arrayContaining(['ai-generated', 'llm-wiki', 'concept']));
    expect(frontmatter.status).toBe('stale');
    expect(await read('change_log.md')).toMatch(/broken-link/);
    expect(await read('change_log.md')).toMatch(/stale-flag/);
  });

  it('draft: pagePlan 을 _drafts 에 적용하고 report 를 쓴다', async () => {
    const result = await applyTier({
      vaultDir: vault,
      tier: 'draft',
      budget: 50,
      plan: {
        date: '2026-06-09',
        draft: [{
          rule: 'new-page',
          pagePlan: {
            source: 'research/a',
            pages: [{
              type: 'synthesis',
              title: 'Synth',
              slug: 'synth',
              aliases: [],
              sources: ['research/a'],
              confidence: 'medium',
              tldr: '요약',
              perspective: '- 합성 [1].',
              links: [],
            }],
          },
        }],
      },
    });

    expect(result.drafted).toContain('_drafts/synthesis/synth.md');
    await expect(read('_drafts/synthesis/synth.md')).resolves.toMatch(/ai-generated/);
    await expect(read('outputs/librarian-2026-06-09.md')).resolves.toMatch(/new-page/);
  });

  it('budget 만큼만 적용한다', async () => {
    const result = await applyTier({
      vaultDir: vault,
      tier: 'auto',
      budget: 1,
      plan: { date: '2026-06-09', auto: [{ rule: 'duplicate-name', slug: 'a' }, { rule: 'duplicate-name', slug: 'b' }] },
    });
    expect(result.applied).toHaveLength(1);
  });
});

describe('librarian CLI', () => {
  it('--report: findings JSON 을 출력한다', async () => {
    await writePage('concepts/a.md', {
      type: 'concept',
      title: 'A',
      slug: 'a',
      sources: ['research/a'],
      related: ['[[ghost]]'],
      tags: ['ai-generated', 'llm-wiki', 'concept'],
      created: '2026-01-01',
      updated: '2026-01-01',
    });
    const { stdout } = await execFileAsync(process.execPath, [
      path.join(process.cwd(), 'lib/wiki/librarian.mjs'),
      '--vault', vault,
      '--report',
      '--date', '2026-06-09',
    ]);
    const parsed = JSON.parse(stdout);
    expect(parsed.findings.some(f => f.rule === 'broken-link' && f.slug === 'a')).toBe(true);
    expect(parsed.classification.auto.some(f => f.rule === 'broken-link')).toBe(true);
  });
});
