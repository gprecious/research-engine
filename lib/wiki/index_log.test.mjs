import { describe, it, expect } from 'vitest';
import { rebuildIndex, appendLog, isIngested } from './index_log.mjs';

describe('rebuildIndex', () => {
  it('AI-generated 콜아웃 포함', () => {
    const md = rebuildIndex([]);
    expect(md).toMatch(/🤖/);
    expect(md).toMatch(/AI-generated/);
  });

  it('type별 그룹·slug 정렬 카탈로그', () => {
    const md = rebuildIndex([
      { type: 'concept', slug: 'moe', title: 'MoE' },
      { type: 'entity', slug: 'transformer', title: 'Transformer' },
      { type: 'concept', slug: 'attention', title: 'Attention' },
    ]);
    expect(md).toMatch(/## Concepts/);
    expect(md).toMatch(/## Entities/);
    expect(md.indexOf('attention')).toBeLessThan(md.indexOf('moe'));
    expect(md).toMatch(/\[\[attention\]\]/);
  });
});

describe('appendLog / isIngested (정확 라인매칭)', () => {
  it('append 후 정확 매칭 true', () => {
    const log = appendLog('', { date: '2026-05-25', action: 'ingest', slug: 'research/2026-04-27-moe' });
    expect(isIngested(log, 'research/2026-04-27-moe')).toBe(true);
  });
  it('접두 부분문자열은 false (오탐 방지)', () => {
    const log = '- [2026-05-25] ingest | research/2026-04-27-moe-followup';
    expect(isIngested(log, 'research/2026-04-27-moe')).toBe(false);
  });
  it('없는 소스 false', () => {
    expect(isIngested('- [2026-05-25] ingest | research/a', 'research/b')).toBe(false);
  });
});
