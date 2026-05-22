import { test, expect } from 'vitest';
import { writeFileSync, unlinkSync } from 'node:fs';
import { loadEnv, requireEnv } from '../../../lib/research_design_env.mjs';

test('loadEnv 가 .env 형식을 읽는다', () => {
  const tmp = '.env.research-design.test';
  writeFileSync(tmp, '# comment\nA=1\nB="two"\nC=three\n\n');
  try {
    const env = loadEnv(tmp);
    expect(env).toEqual({ A: '1', B: 'two', C: 'three' });
  } finally {
    unlinkSync(tmp);
  }
});

test('requireEnv 가 누락 키를 알린다', () => {
  expect(() => requireEnv(['NEVER_SET_X'], {})).toThrow(/missing env: NEVER_SET_X/);
});
