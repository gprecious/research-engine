import { describe, it, expect } from 'vitest';
import {
  emptyLedger,
  bumpAfterResearch,
  shouldSuggest,
  markSuggested,
  resetAfterDream,
  rebuildFromManifest
} from './ledger.mjs';

describe('emptyLedger', () => {
  it('초기 상태는 null + 빈 배열', () => {
    expect(emptyLedger()).toEqual({
      version: 1,
      last_dream_run_id: null,
      last_dream_at: null,
      sessions_since_last_dream: [],
      suggestion_threshold: 5,
      suggestion_shown_at: null,
      last_shown_count: 0
    });
  });
});

describe('bumpAfterResearch', () => {
  it('새 슬러그를 카운터에 추가', () => {
    const next = bumpAfterResearch(emptyLedger(), 'new-slug');
    expect(next.sessions_since_last_dream).toEqual(['new-slug']);
  });

  it('중복 슬러그는 추가하지 않음', () => {
    const l = bumpAfterResearch(emptyLedger(), 's1');
    const next = bumpAfterResearch(l, 's1');
    expect(next.sessions_since_last_dream).toEqual(['s1']);
  });
});

describe('shouldSuggest', () => {
  it('카운터 < threshold이면 false', () => {
    const l = { ...emptyLedger(), sessions_since_last_dream: ['a', 'b', 'c', 'd'] };
    expect(shouldSuggest(l)).toBe(false);
  });

  it('카운터 == threshold이고 suggestion 미노출이면 true', () => {
    const l = { ...emptyLedger(), sessions_since_last_dream: ['a', 'b', 'c', 'd', 'e'] };
    expect(shouldSuggest(l)).toBe(true);
  });

  it('카운터 6 — 이미 5에서 보여줬다면 false', () => {
    const l = {
      ...emptyLedger(),
      sessions_since_last_dream: ['a', 'b', 'c', 'd', 'e', 'f'],
      suggestion_shown_at: '2026-05-23T00:00:00+09:00',
      last_shown_count: 5
    };
    expect(shouldSuggest(l)).toBe(false);
  });

  it('카운터 10 — 5에서 보여준 뒤 +5 누적 시 true', () => {
    const l = {
      ...emptyLedger(),
      sessions_since_last_dream: Array.from({ length: 10 }, (_, i) => `s${i}`),
      suggestion_shown_at: '2026-05-23T00:00:00+09:00',
      last_shown_count: 5
    };
    expect(shouldSuggest(l)).toBe(true);
  });

  it('threshold 사용자 변경 (3)', () => {
    const l = { ...emptyLedger(), suggestion_threshold: 3, sessions_since_last_dream: ['a', 'b', 'c'] };
    expect(shouldSuggest(l)).toBe(true);
  });
});

describe('markSuggested + resetAfterDream', () => {
  it('markSuggested는 last_shown_count와 timestamp 갱신', () => {
    const l = { ...emptyLedger(), sessions_since_last_dream: ['a', 'b', 'c', 'd', 'e'] };
    const next = markSuggested(l, '2026-05-23T00:00:00+09:00');
    expect(next.suggestion_shown_at).toBe('2026-05-23T00:00:00+09:00');
    expect(next.last_shown_count).toBe(5);
  });

  it('resetAfterDream은 모든 상태 초기화', () => {
    const l = {
      ...emptyLedger(),
      sessions_since_last_dream: ['a', 'b', 'c', 'd', 'e'],
      suggestion_shown_at: '2026-05-23T00:00:00+09:00',
      last_shown_count: 5
    };
    const next = resetAfterDream(l, 'drm_2026-06-01', '2026-06-01T10:00:00+09:00');
    expect(next.sessions_since_last_dream).toEqual([]);
    expect(next.last_dream_run_id).toBe('drm_2026-06-01');
    expect(next.last_dream_at).toBe('2026-06-01T10:00:00+09:00');
    expect(next.suggestion_shown_at).toBeNull();
    expect(next.last_shown_count).toBe(0);
  });
});

describe('rebuildFromManifest', () => {
  it('manifest sessions + dreams로부터 ledger 재구성', () => {
    const manifest = {
      sessions: [
        { slug: 's-old', created: '2026-04-01' },
        { slug: 's-after-1', created: '2026-05-15' },
        { slug: 's-after-2', created: '2026-05-20' }
      ],
      dreams: [{ run_id: 'drm_2026-05-10', created: '2026-05-10', status: 'active' }]
    };
    const l = rebuildFromManifest(manifest);
    expect(l.last_dream_run_id).toBe('drm_2026-05-10');
    expect(l.last_dream_at).toBe('2026-05-10');
    expect(l.sessions_since_last_dream).toEqual(['s-after-1', 's-after-2']);
  });

  it('dreams가 비어 있으면 모든 세션이 since', () => {
    const manifest = {
      sessions: [{ slug: 'a', created: '2026-01-01' }, { slug: 'b', created: '2026-02-01' }],
      dreams: []
    };
    const l = rebuildFromManifest(manifest);
    expect(l.last_dream_run_id).toBeNull();
    expect(l.sessions_since_last_dream).toEqual(['a', 'b']);
  });
});
