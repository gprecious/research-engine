import { describe, it, expect } from 'vitest';
import { ensureTags, parsePage, serializePage, validateFrontmatter } from './frontmatter.mjs';

const fm = {
  type: 'concept', title: 'Mixture of Experts', slug: 'mixture-of-experts',
  aliases: ['MoE'], sources: ['research/2026-04-27-moe'], related: ['[[transformer]]'],
  confidence: 'high', created: '2026-05-25', updated: '2026-05-26',
  tags: ['ai-generated', 'llm-wiki', 'concept']
};

describe('serialize/parse round-trip', () => {
  it('frontmatter·body 보존', () => {
    const raw = serializePage({ frontmatter: fm, body: '## TL;DR\n본문' });
    const { frontmatter, body } = parsePage(raw);
    expect(frontmatter.slug).toBe('mixture-of-experts');
    expect(frontmatter.sources).toEqual(['research/2026-04-27-moe']);
    expect(body.trim()).toBe('## TL;DR\n본문');
  });
});

describe('validateFrontmatter', () => {
  it('유효 → ok', () => { expect(validateFrontmatter(fm).ok).toBe(true); });
  it('type 오류 → error', () => {
    const r = validateFrontmatter({ ...fm, type: 'note' });
    expect(r.ok).toBe(false); expect(r.errors.join(' ')).toMatch(/type/);
  });
  it('sources 비배열 → error', () => { expect(validateFrontmatter({ ...fm, sources: 'x' }).ok).toBe(false); });
  it('related 누락 → error', () => { const { related, ...rest } = fm; expect(validateFrontmatter(rest).ok).toBe(false); });
  it('confidence 비정상 → error', () => { expect(validateFrontmatter({ ...fm, confidence: 'maybe' }).ok).toBe(false); });
  it('slug에 한글 → error (ASCII만)', () => { expect(validateFrontmatter({ ...fm, slug: '전문가-혼합' }).ok).toBe(false); });
  it('slug 대문자/공백 → error', () => { expect(validateFrontmatter({ ...fm, slug: 'Bad Slug' }).ok).toBe(false); });
});

describe('tags', () => {
  it('ensureTags 가 ai-generated/llm-wiki/type 보장 + 기존 보존', () => {
    const out = ensureTags({ type: 'concept', tags: ['x'] });
    expect(out.tags).toEqual(expect.arrayContaining(['x', 'ai-generated', 'llm-wiki', 'concept']));
    expect(new Set(out.tags).size).toBe(out.tags.length);
  });

  it('validate: tags 누락 → error', () => {
    const { tags, ...rest } = fm;
    expect(validateFrontmatter(rest).ok).toBe(false);
  });

  it('validate: type synthesis/ephemeral 허용', () => {
    expect(validateFrontmatter({ ...fm, type: 'synthesis', tags: ['ai-generated', 'llm-wiki', 'synthesis'] }).ok).toBe(true);
    expect(validateFrontmatter({ ...fm, type: 'ephemeral', tags: ['ai-generated', 'llm-wiki', 'ephemeral'] }).ok).toBe(true);
  });
});
