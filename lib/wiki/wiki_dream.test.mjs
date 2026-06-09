import { describe, it, expect, beforeEach } from 'vitest';
import { execFile } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { collectWikiCorpus, applyWikiDream } from './wiki_dream.mjs';
import { parsePage, serializePage } from './frontmatter.mjs';

const execFileAsync = promisify(execFile);

let vault;
beforeEach(async () => {
  vault = await fs.mkdtemp(path.join(os.tmpdir(), 'wiki-dream-'));
});

async function writePage(rel, fm, body) {
  const abs = path.join(vault, rel);
  await fs.mkdir(path.dirname(abs), { recursive: true });
  await fs.writeFile(abs, serializePage({ frontmatter: fm, body }));
}

const page = (slug, title, source) => ({
  type: 'concept',
  title,
  slug,
  aliases: [],
  sources: [source],
  related: [],
  tags: ['ai-generated', 'llm-wiki', 'concept'],
  confidence: 'medium',
  created: '2026-06-01',
  updated: '2026-06-01',
});

describe('collectWikiCorpus', () => {
  it('concepts/entities 요약만 수집하고 drafts 는 제외한다', async () => {
    await writePage('concepts/router.md', page('router', 'Router', 'research/a'), '## TL;DR\n라우터 요약\n\n## 출처별 관점\n\n### research/a\n- 주장 [1]\n');
    await writePage('entities/model-x.md', { ...page('model-x', 'Model X', 'research/b'), type: 'entity', tags: ['ai-generated', 'llm-wiki', 'entity'] }, '## TL;DR\n모델 요약\n');
    await writePage('_drafts/concepts/ignored.md', page('ignored', 'Ignored', 'research/c'), '## TL;DR\n무시\n');

    const corpus = await collectWikiCorpus({ vaultDir: vault });

    expect(corpus.map(p => p.slug)).toEqual(['router', 'model-x']);
    expect(corpus[0]).toMatchObject({ type: 'concept', title: 'Router', summary: '라우터 요약' });
  });
});

describe('applyWikiDream', () => {
  it('synthesis draft, todo, reflect_state 를 쓴다', async () => {
    const result = await applyWikiDream({
      vaultDir: vault,
      date: '2026-06-09',
      synthesis: {
        slug: 'routing-constraints',
        title: 'Routing Constraints',
        summary: '라우팅 제약은 모델과 운영 양쪽에서 반복된다.',
        evidenceSlugs: ['router', 'model-x'],
        sources: ['research/a', 'research/b'],
      },
      todo: {
        slug: 'routing-gap',
        title: 'Routing Gap',
        question: '라우팅 제약을 정량화할 새 리서치가 필요한가?',
      },
    });

    expect(result.synthesis).toBe('_drafts/synthesis/routing-constraints.md');
    expect(result.todo).toBe('_todos/routing-gap.md');
    const { frontmatter, body } = parsePage(await fs.readFile(path.join(vault, result.synthesis), 'utf8'));
    expect(frontmatter.type).toBe('synthesis');
    expect(frontmatter.tags).toEqual(expect.arrayContaining(['ai-generated', 'llm-wiki', 'synthesis']));
    expect(frontmatter.related).toEqual(['[[router]]', '[[model-x]]']);
    expect(body).toMatch(/Evidence pages/);
    expect(await fs.readFile(path.join(vault, result.todo), 'utf8')).toMatch(/라우팅 제약/);
    const state = JSON.parse(await fs.readFile(path.join(vault, '_index/reflect_state.json'), 'utf8'));
    expect(state.runs).toHaveLength(1);
    expect(state.runs[0].synthesis).toBe('routing-constraints');
  });

  it('synthesis 는 2개 이상 evidence slug 를 요구한다', async () => {
    await expect(applyWikiDream({
      vaultDir: vault,
      date: '2026-06-09',
      synthesis: { slug: 'weak', title: 'Weak', summary: '약함', evidenceSlugs: ['one'], sources: ['research/a'] },
    })).rejects.toThrow(/evidence/);
  });

  it('CLI apply 는 JSON 입력으로 draft 산출한다', async () => {
    const input = path.join(vault, 'dream.json');
    await fs.writeFile(input, JSON.stringify({
      synthesis: {
        slug: 'routing-constraints',
        title: 'Routing Constraints',
        summary: '요약',
        evidenceSlugs: ['router', 'model-x'],
        sources: ['research/a', 'research/b'],
      },
      todo: { slug: 'routing-gap', title: 'Routing Gap', question: '질문' },
    }));

    const { stdout } = await execFileAsync(process.execPath, [
      path.join(process.cwd(), 'lib/wiki/wiki_dream.mjs'),
      '--vault', vault,
      '--apply', input,
      '--date', '2026-06-09',
    ]);

    expect(JSON.parse(stdout).synthesis).toBe('_drafts/synthesis/routing-constraints.md');
  });
});
