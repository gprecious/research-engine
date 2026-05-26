import { describe, it, expect } from 'vitest';
import { lintVault } from './lint.mjs';

const pages = [
  { slug: 'a', type: 'concept', frontmatter: { title: 'A', sources: ['research/x'], related: ['[[b]]'] }, body: '## 출처별 관점\n### research/x\n- 주장 [1]' },
  { slug: 'b', type: 'concept', frontmatter: { title: 'B', sources: [], related: [] }, body: '## 출처별 관점\n무출처 주장' },                 // unsourced
  { slug: 'c', type: 'concept', frontmatter: { title: 'C', sources: ['research/y'], related: ['[[ghost]]'] }, body: '본문' },               // broken-link
  { slug: 'd', type: 'entity', frontmatter: { title: 'D', sources: ['research/z'], related: [] }, body: '링크 없음' },                      // orphan
  { slug: 'e', type: 'concept', frontmatter: { title: 'A', sources: ['research/w'], related: ['[[a]]'] }, body: '## 출처별 관점\n### research/w\n- 주장 [1]' }, // duplicate-title
];

describe('lintVault', () => {
  const { findings } = lintVault({ pages });
  const has = (rule, slug) => findings.some(f => f.rule === rule && f.slug === slug);
  it('무출처', () => expect(has('unsourced', 'b')).toBe(true));
  it('끊긴 링크(related)', () => expect(has('broken-link', 'c')).toBe(true));
  it('고아(인바운드·아웃바운드 없음)', () => expect(has('orphan', 'd')).toBe(true));
  it('b는 a가 링크 → orphan 아님', () => expect(has('orphan', 'b')).toBe(false));
  it('중복 이름 (a, e — title 정규화 후 동일)', () => { expect(has('duplicate-name', 'a')).toBe(true); expect(has('duplicate-name', 'e')).toBe(true); });
  it('정상 a는 무출처/고아 아님', () => { expect(has('unsourced', 'a')).toBe(false); expect(has('orphan', 'a')).toBe(false); });
});
