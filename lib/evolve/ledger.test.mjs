import { describe, it, expect } from 'vitest';
import { initLedger, promote, reject, getCurrent } from './ledger.mjs';

describe('ledger', () => {
  it('initLedger seeds an adapter with version 1', () => {
    const l = initLedger();
    const l2 = promote(l, 'youtube-adapter', {
      version: 1,
      metrics: { judge_score: 0.62, source_count: 18, type_diversity: 4, latency_inv: 0.01 },
      ci_lower: null,
      promoted_at: '2026-05-24T00:00:00Z',
    });
    expect(getCurrent(l2, 'youtube-adapter').version).toBe(1);
    expect(l2.adapters['youtube-adapter'].history).toHaveLength(1);
    expect(l2.adapters['youtube-adapter'].frontier).toHaveLength(1);
  });

  it('promote bumps current_version and appends history', () => {
    let l = initLedger();
    l = promote(l, 'youtube-adapter', { version: 1, metrics: { judge_score: 0.6, source_count: 10, type_diversity: 3, latency_inv: 0.01 }, ci_lower: null, promoted_at: 't1' });
    l = promote(l, 'youtube-adapter', { version: 2, metrics: { judge_score: 0.7, source_count: 12, type_diversity: 3, latency_inv: 0.01 }, ci_lower: 0.05, promoted_at: 't2' });
    expect(getCurrent(l, 'youtube-adapter').version).toBe(2);
    expect(l.adapters['youtube-adapter'].history).toHaveLength(2);
  });

  it('reject keeps Pareto-non-dominated in frontier, dominated goes to rejected', () => {
    let l = initLedger();
    l = promote(l, 'youtube-adapter', { version: 1, metrics: { judge_score: 0.6, source_count: 10, type_diversity: 3, latency_inv: 0.01 }, ci_lower: null, promoted_at: 't1' });
    // candidate v2: worse judge, but better source_count → non-dominated
    l = reject(l, 'youtube-adapter', { version: 2, metrics: { judge_score: 0.55, source_count: 14, type_diversity: 3, latency_inv: 0.01 }, ci_lower: -0.02, rejected_at: 't2' });
    expect(l.adapters['youtube-adapter'].frontier).toHaveLength(2);
    expect(l.adapters['youtube-adapter'].rejected).toHaveLength(0);
    // candidate v3: dominated by v1 on every axis
    l = reject(l, 'youtube-adapter', { version: 3, metrics: { judge_score: 0.5, source_count: 8, type_diversity: 2, latency_inv: 0.005 }, ci_lower: -0.10, rejected_at: 't3' });
    expect(l.adapters['youtube-adapter'].rejected).toHaveLength(1);
    expect(l.adapters['youtube-adapter'].rejected[0].version).toBe(3);
  });
});
