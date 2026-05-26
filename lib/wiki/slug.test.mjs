import { describe, it, expect } from 'vitest';
import { slugify } from './slug.mjs';

describe('slugify', () => {
  it('공백·대소문자 → ASCII kebab', () => {
    expect(slugify('Mixture of Experts')).toBe('mixture-of-experts');
  });
  it('특수문자 런 접고 양끝 트림', () => {
    expect(slugify('  RAG: retrieval!! ')).toBe('rag-retrieval');
  });
  it('비ASCII(한글 only) → 결정적 해시 fallback (ASCII 보장)', () => {
    const s = slugify('전문가 혼합');
    expect(s).toMatch(/^n-[0-9a-f]{6}$/);
    expect(slugify('전문가 혼합')).toBe(s); // 결정적
  });
  it('빈/널 → 빈 문자열', () => {
    expect(slugify('')).toBe('');
    expect(slugify(null)).toBe('');
  });
});
