import { describe, it, expect } from 'vitest';
import { scoreSession, topK } from './similarity.mjs';

const target = {
  input_type: 'youtube',
  topics: ['agent memory', 'dreaming', 'managed agents'],
  intent: { purpose_tokens: ['memory', 'dreaming', 'research', 'engine'] }
};

describe('scoreSession', () => {
  it('input_type 동치 시 가중치 3 적용', () => {
    const c = { input_type: 'youtube', topics: [], intent: { purpose_tokens: [] } };
    expect(scoreSession(target, c)).toBe(3);
  });

  it('input_type 불일치 시 그 항목은 0', () => {
    const c = { input_type: 'arxiv', topics: [], intent: { purpose_tokens: [] } };
    expect(scoreSession(target, c)).toBe(0);
  });

  it('topics 교집합 수에 가중치 2', () => {
    const c = { input_type: 'arxiv', topics: ['agent memory', 'dreaming', 'unrelated'], intent: { purpose_tokens: [] } };
    expect(scoreSession(target, c)).toBe(4);
  });

  it('purpose_tokens 교집합 수에 가중치 1', () => {
    const c = { input_type: 'arxiv', topics: [], intent: { purpose_tokens: ['memory', 'research', 'unrelated'] } };
    expect(scoreSession(target, c)).toBe(2);
  });

  it('세 가중치 합산', () => {
    const c = {
      input_type: 'youtube',
      topics: ['agent memory', 'dreaming'],
      intent: { purpose_tokens: ['memory', 'research'] }
    };
    expect(scoreSession(target, c)).toBe(3 + 4 + 2);
  });
});

describe('topK', () => {
  const candidates = [
    { slug: 'a', input_type: 'youtube', topics: ['agent memory'], intent: { purpose_tokens: [] }, created: '2026-05-01' },
    { slug: 'b', input_type: 'arxiv', topics: [], intent: { purpose_tokens: ['memory'] }, created: '2026-05-02' },
    { slug: 'c', input_type: 'youtube', topics: ['agent memory', 'dreaming'], intent: { purpose_tokens: ['memory'] }, created: '2026-05-03' },
    { slug: 'd', input_type: 'blog', topics: ['unrelated'], intent: { purpose_tokens: [] }, created: '2026-05-04' }
  ];

  it('가장 점수 높은 K개 반환', () => {
    const res = topK(target, candidates, 2);
    expect(res.map(r => r.slug)).toEqual(['c', 'a']);
  });

  it('점수 0인 후보는 제외 (d 제외)', () => {
    const res = topK(target, candidates, 10);
    expect(res.map(r => r.slug)).toEqual(['c', 'a', 'b']);
  });

  it('K가 후보 수보다 크면 가능한 만큼만', () => {
    const res = topK(target, candidates, 100);
    expect(res.length).toBe(3);
  });

  it('동점 시 created desc 안정 정렬', () => {
    const ties = [
      { slug: 't1', input_type: 'youtube', topics: [], intent: { purpose_tokens: [] }, created: '2026-05-01' },
      { slug: 't2', input_type: 'youtube', topics: [], intent: { purpose_tokens: [] }, created: '2026-05-02' }
    ];
    const res = topK(target, ties, 2);
    expect(res.map(r => r.slug)).toEqual(['t2', 't1']);
  });

  it('target.slug과 같은 후보 self-exclusion', () => {
    const t = { ...target, slug: 'c' };
    const res = topK(t, candidates, 10);
    expect(res.map(r => r.slug)).not.toContain('c');
  });
});
