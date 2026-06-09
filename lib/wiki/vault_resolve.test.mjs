import { describe, it, expect } from 'vitest';
import { resolveVault } from './vault_resolve.mjs';

const cfg = () => ({
  vaults: {
    a: { path: '/Users/x/Documents/obsidian/harry', open: true, ts: 200 },
    b: { path: '/icloud/harry', open: false, ts: 100 },
    c: { path: '/Users/x/other', open: true, ts: 300 },
  },
});

describe('resolveVault precedence', () => {
  it('1) WIKI_VAULT 절대경로가 최우선', () => {
    const r = resolveVault({
      env: { WIKI_VAULT: '/abs/wiki', LLM_OBSIDIAN_VAULT_NAME: 'harry' },
      cwd: '/proj',
      readConfig: cfg,
    });
    expect(r.dir).toBe('/abs/wiki');
    expect(r.mode).toBe('explicit');
  });

  it('2) 이름 → obsidian.json 해석 + 하위폴더, open/ts 우선', () => {
    const r = resolveVault({
      env: { LLM_OBSIDIAN_VAULT_NAME: 'harry', LLM_WIKI_SUBDIR: 'LLM-Wiki' },
      cwd: '/proj',
      readConfig: cfg,
    });
    expect(r.dir).toBe('/Users/x/Documents/obsidian/harry/LLM-Wiki');
    expect(r.mode).toBe('name');
  });

  it('2b) SUBDIR 기본값 LLM-Wiki', () => {
    const r = resolveVault({
      env: { LLM_OBSIDIAN_VAULT_NAME: 'harry' },
      cwd: '/proj',
      readConfig: cfg,
    });
    expect(r.dir).toBe('/Users/x/Documents/obsidian/harry/LLM-Wiki');
  });

  it('3) env 없음 → <cwd>/wiki 폴백', () => {
    const r = resolveVault({ env: {}, cwd: '/proj', readConfig: () => null });
    expect(r.dir).toBe('/proj/wiki');
    expect(r.mode).toBe('default');
  });

  it('3b) 미등록 vault 이름 → 폴백 + ok=false', () => {
    const r = resolveVault({
      env: { LLM_OBSIDIAN_VAULT_NAME: 'nope' },
      cwd: '/proj',
      readConfig: cfg,
    });
    expect(r.dir).toBe('/proj/wiki');
    expect(r.ok).toBe(false);
  });
});
