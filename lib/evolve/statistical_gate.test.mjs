import { describe, it, expect } from 'vitest';
import { pairedBootstrapCI, gateDecision } from './statistical_gate.mjs';

describe('pairedBootstrapCI', () => {
  it('returns CI > 0 for consistently positive deltas', () => {
    // candidate beats current by ~0.1 on every paired trial
    const current = [0.50, 0.52, 0.48, 0.51, 0.49, 0.50, 0.52, 0.48];
    const candidate = [0.60, 0.62, 0.58, 0.61, 0.59, 0.60, 0.62, 0.58];
    const ci = pairedBootstrapCI(current, candidate, { iters: 2000, seed: 42 });
    expect(ci.mean).toBeCloseTo(0.10, 2);
    expect(ci.lower).toBeGreaterThan(0);
    expect(ci.upper).toBeLessThan(0.2);
  });

  it('returns CI spanning 0 for noisy zero-mean delta', () => {
    const current = [0.50, 0.55, 0.45, 0.60, 0.40, 0.50, 0.55, 0.45];
    const candidate = [0.55, 0.50, 0.50, 0.55, 0.45, 0.48, 0.52, 0.50];
    const ci = pairedBootstrapCI(current, candidate, { iters: 2000, seed: 42 });
    expect(ci.lower).toBeLessThan(0);
    expect(ci.upper).toBeGreaterThan(0);
  });

  it('throws on length mismatch', () => {
    expect(() =>
      pairedBootstrapCI([1, 2], [1, 2, 3], { iters: 100, seed: 1 })
    ).toThrow(/length/);
  });
});

describe('gateDecision', () => {
  it('ACCEPT when CI.lower > 0', () => {
    expect(gateDecision({ lower: 0.01, upper: 0.10, mean: 0.05 })).toBe('accept');
  });
  it('REJECT when CI.upper < 0', () => {
    expect(gateDecision({ lower: -0.10, upper: -0.01, mean: -0.05 })).toBe('reject');
  });
  it('HOLD when CI spans 0', () => {
    expect(gateDecision({ lower: -0.05, upper: 0.05, mean: 0.0 })).toBe('hold');
  });
});
