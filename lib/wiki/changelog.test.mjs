import { describe, it, expect } from 'vitest';
import { appendChangeLog } from './changelog.mjs';

describe('appendChangeLog', () => {
  it('빈 로그에 date/kind/detail 라인을 추가한다', () => {
    const out = appendChangeLog('', { date: '2026-06-09', kind: 'stale-flag', detail: 'old status: stale' });
    expect(out).toBe('- [2026-06-09] stale-flag | old status: stale\n');
  });

  it('기존 로그를 보존하고 뒤에만 추가한다', () => {
    const existing = '- [2026-06-08] tag-fix | a\n';
    const out = appendChangeLog(existing, { date: '2026-06-09', kind: 'broken-link', detail: 'a removed [[ghost]]' });
    expect(out).toBe(`${existing}- [2026-06-09] broken-link | a removed [[ghost]]\n`);
  });
});
