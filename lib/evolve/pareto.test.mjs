import { describe, it, expect } from 'vitest';
import { dominates, paretoFront } from './pareto.mjs';

describe('dominates', () => {
  it('a dominates b when a >= b on all axes and > on at least one (maximize)', () => {
    expect(dominates({ x: 1, y: 1 }, { x: 0, y: 0 })).toBe(true);
    expect(dominates({ x: 1, y: 1 }, { x: 1, y: 0 })).toBe(true);
    expect(dominates({ x: 1, y: 1 }, { x: 1, y: 1 })).toBe(false);
    expect(dominates({ x: 1, y: 0 }, { x: 0, y: 1 })).toBe(false);
  });
});

describe('paretoFront', () => {
  it('keeps only non-dominated points', () => {
    const pts = [
      { id: 'a', x: 1, y: 1 },
      { id: 'b', x: 0, y: 0 }, // dominated by a
      { id: 'c', x: 2, y: 0 },
      { id: 'd', x: 0, y: 2 },
    ];
    const front = paretoFront(pts, ['x', 'y']);
    expect(front.map((p) => p.id).sort()).toEqual(['a', 'c', 'd']);
  });
});
