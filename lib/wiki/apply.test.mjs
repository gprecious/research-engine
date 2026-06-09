import { describe, it, expect, beforeEach } from 'vitest';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { applyIngest } from './apply.mjs';
import { parsePage } from './frontmatter.mjs';

let vault;
beforeEach(async () => { vault = await fs.mkdtemp(path.join(os.tmpdir(), 'wiki-')); });

const plan = {
  source: 'research/2026-04-27-moe',
  pages: [{
    type: 'concept', title: 'Mixture of Experts', slug: 'mixture-of-experts',
    aliases: ['MoE'], sources: ['research/2026-04-27-moe'], confidence: 'high',
    tldr: '라우터가 토큰을 일부 전문가에게만 보낸다.',
    perspective: '- top-k 전문가 선택 [1].', links: ['attention-mechanism'],
  }],
};
const read = (p) => fs.readFile(path.join(vault, p), 'utf8');

describe('applyIngest', () => {
  it('새 페이지: 섹션 본문·related·index·log 1줄', async () => {
    const r = await applyIngest({ vaultDir: vault, pagePlan: plan, date: '2026-05-25' });
    expect(r.created).toContain('concepts/mixture-of-experts.md');
    const { frontmatter, body } = parsePage(await read('concepts/mixture-of-experts.md'));
    expect(frontmatter.tags).toEqual(expect.arrayContaining(['ai-generated', 'llm-wiki', 'concept']));
    expect(frontmatter.related).toEqual(['[[attention-mechanism]]']);
    expect(body).toMatch(/## TL;DR/);
    expect(body).toMatch(/### research\/2026-04-27-moe/);
    expect(body).toMatch(/## 관련 개념/);
    expect(body).toMatch(/\[\[attention-mechanism\]\]/);
    expect(await read('index.md')).toMatch(/\[\[mixture-of-experts\]\]/);
    expect((await read('log.md')).match(/ingest \| research\/2026-04-27-moe/g)).toHaveLength(1);
  });

  it('같은 소스 두 번: 멱등(중복 섹션·중복 log 없음)', async () => {
    await applyIngest({ vaultDir: vault, pagePlan: plan, date: '2026-05-25' });
    await applyIngest({ vaultDir: vault, pagePlan: plan, date: '2026-05-26' });
    const body = (await read('concepts/mixture-of-experts.md'));
    expect(body.match(/### research\/2026-04-27-moe/g)).toHaveLength(1);
    expect(body.match(/## 관련 개념/g)).toHaveLength(1);
    expect((await read('log.md')).match(/ingest \|/g)).toHaveLength(1);
  });

  it('다른 소스 merge: sources 합집합 + 섹션 2개 + updated 갱신', async () => {
    await applyIngest({ vaultDir: vault, pagePlan: plan, date: '2026-05-25' });
    const p2 = structuredClone(plan);
    p2.source = 'research/2026-05-01-moe-followup';
    p2.pages[0].sources = ['research/2026-05-01-moe-followup'];
    p2.pages[0].perspective = '- 로드밸런싱 개선 [1].';
    p2.pages[0].links = ['transformer'];
    const r = await applyIngest({ vaultDir: vault, pagePlan: p2, date: '2026-05-26' });
    expect(r.merged).toContain('concepts/mixture-of-experts.md');
    const { frontmatter, body } = parsePage(await read('concepts/mixture-of-experts.md'));
    expect(frontmatter.sources).toEqual(['research/2026-04-27-moe', 'research/2026-05-01-moe-followup']);
    expect(frontmatter.related.sort()).toEqual(['[[attention-mechanism]]', '[[transformer]]']);
    expect(frontmatter.updated).toBe('2026-05-26');
    expect(body.match(/### research\//g)).toHaveLength(2);
  });

  it('누적 sources merge: 섹션 키는 pagePlan.source (sources[0] 아님)', async () => {
    await applyIngest({ vaultDir: vault, pagePlan: plan, date: '2026-05-25' });
    const p2 = structuredClone(plan);
    p2.source = 'research/2026-05-01-moe-followup';
    // LLM이 누적 sources를 원본 먼저 순서로 내보낸 경우(sources[0] = 이전 세션)
    p2.pages[0].sources = ['research/2026-04-27-moe', 'research/2026-05-01-moe-followup'];
    p2.pages[0].perspective = '- 후속 관점 [1].';
    await applyIngest({ vaultDir: vault, pagePlan: p2, date: '2026-05-26' });
    const { body } = parsePage(await read('concepts/mixture-of-experts.md'));
    expect(body).toMatch(/### research\/2026-04-27-moe\n/);        // 원본 섹션 보존(덮어쓰기 아님)
    expect(body).toMatch(/### research\/2026-05-01-moe-followup/); // 새 세션 섹션은 pagePlan.source 키로
    expect(body).toMatch(/후속 관점/);
  });

  it('다중 줄 perspective 라운드트립: 모든 줄 보존 (앵커 lookahead 회귀 방지)', async () => {
    const ml = structuredClone(plan);
    ml.pages[0].perspective = '- 첫째 줄 [1].\n- 둘째 줄 [2].\n- 셋째 줄 [3].';
    await applyIngest({ vaultDir: vault, pagePlan: ml, date: '2026-05-25' });
    // 다른 세션으로 merge → 기존 3줄 섹션을 parseBody로 재파싱해야 함(절단되면 손실)
    const p2 = structuredClone(plan);
    p2.source = 'research/2026-05-02-x';
    p2.pages[0].sources = ['research/2026-05-02-x'];
    p2.pages[0].perspective = '- 새 줄 [1].';
    await applyIngest({ vaultDir: vault, pagePlan: p2, date: '2026-05-26' });
    const { body } = parsePage(await read('concepts/mixture-of-experts.md'));
    expect(body).toMatch(/첫째 줄/);
    expect(body).toMatch(/둘째 줄/);
    expect(body).toMatch(/셋째 줄/); // 회귀(줄끝 $ 절단) 시 사라짐
  });

  it('원자성: 멀티페이지 중 하나라도 invalid면 아무것도 안 쓴다', async () => {
    const bad = structuredClone(plan);
    // sources 는 불변식(pagePlan.source 포함)을 만족시키되 type 만 위반 → 검증 단계서 throw
    bad.pages.push({ type: 'note', title: 'X', slug: 'x', sources: ['research/2026-04-27-moe'], tldr: '', perspective: '', links: [] });
    await expect(applyIngest({ vaultDir: vault, pagePlan: bad, date: '2026-05-25' })).rejects.toThrow(/type/);
    await expect(read('concepts/mixture-of-experts.md')).rejects.toThrow(); // 첫 페이지도 안 쓰임
    await expect(read('log.md')).rejects.toThrow();
  });

  it('경로 탈출 거부: slug에 ../ 가 있으면 throw하고 vault 밖에 안 쓴다', async () => {
    const ev = structuredClone(plan);
    ev.pages[0].slug = '../../outside';
    await expect(applyIngest({ vaultDir: vault, pagePlan: ev, date: '2026-05-25' }))
      .rejects.toThrow(/slug|escapes/);
    await expect(fs.readFile(path.join(vault, '..', '..', 'outside.md'), 'utf8')).rejects.toThrow();
  });
});
