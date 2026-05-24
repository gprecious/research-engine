import { describe, it, expect } from 'vitest';
import { extractRegions, replaceRegion } from './extract_evolvable.mjs';

describe('extractRegions', () => {
  it('parses two non-nested regions', () => {
    const src = [
      '# title',
      'before',
      '<!-- evolvable:a -->',
      'AAA',
      '<!-- /evolvable -->',
      'between',
      '<!-- evolvable:b -->',
      'BBB',
      'BBB2',
      '<!-- /evolvable -->',
      'after',
    ].join('\n');
    const regions = extractRegions(src);
    expect(regions).toEqual([
      { id: 'a', body: 'AAA' },
      { id: 'b', body: 'BBB\nBBB2' },
    ]);
  });

  it('returns empty array when no markers', () => {
    expect(extractRegions('plain text')).toEqual([]);
  });

  it('throws on unbalanced markers', () => {
    expect(() =>
      extractRegions('<!-- evolvable:a -->\nfoo\n')
    ).toThrow(/unbalanced/i);
  });

  it('throws on nested markers', () => {
    expect(() =>
      extractRegions(
        '<!-- evolvable:a -->\n<!-- evolvable:b -->\nx\n<!-- /evolvable -->\n<!-- /evolvable -->'
      )
    ).toThrow(/nested/i);
  });
});

describe('replaceRegion', () => {
  it('replaces a region body by id', () => {
    const src = [
      '<!-- evolvable:a -->',
      'old',
      '<!-- /evolvable -->',
    ].join('\n');
    const out = replaceRegion(src, 'a', 'new\nbody');
    expect(out).toBe(
      '<!-- evolvable:a -->\nnew\nbody\n<!-- /evolvable -->'
    );
  });

  it('throws if id not found', () => {
    expect(() => replaceRegion('plain', 'x', 'y')).toThrow(/not found/);
  });

  it('replaces body even when source has no inner newlines', () => {
    const src = '<!-- evolvable:a -->one-line<!-- /evolvable -->';
    const out = replaceRegion(src, 'a', 'new');
    expect(out).toBe('<!-- evolvable:a -->\nnew\n<!-- /evolvable -->');
  });
});
