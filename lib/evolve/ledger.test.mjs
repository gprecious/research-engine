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

  it('promote shed-out: when new promoted entry dominates a frontier member, the shed member moves to rejected', () => {
    let l = initLedger();
    // v1: middle metrics
    l = promote(l, 'x', { version: 1, metrics: { judge_score: 0.5, source_count: 5, type_diversity: 2, latency_inv: 0.01 }, ci_lower: null, promoted_at: 't1' });
    // v2 rejected but non-dominated (better source_count, worse judge) — stays in frontier
    l = reject(l, 'x', { version: 2, metrics: { judge_score: 0.45, source_count: 9, type_diversity: 2, latency_inv: 0.01 }, ci_lower: -0.05, rejected_at: 't2' });
    expect(l.adapters['x'].frontier.map(f => f.version).sort()).toEqual([1, 2]);
    // v3 promoted, dominates v1 on every axis (and v2 since judge much higher; also source >= v2)
    l = promote(l, 'x', { version: 3, metrics: { judge_score: 0.9, source_count: 10, type_diversity: 3, latency_inv: 0.02 }, ci_lower: 0.1, promoted_at: 't3' });
    // v1 and v2 both dominated → should be on rejected, frontier = [v3]
    expect(l.adapters['x'].frontier.map(f => f.version)).toEqual([3]);
    expect(l.adapters['x'].rejected.map(f => f.version).sort()).toEqual([1, 2]);
  });
});
