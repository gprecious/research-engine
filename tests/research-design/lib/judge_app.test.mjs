import { test, expect, describe } from 'vitest';
import { judge } from '../../../scripts/judge_app.mjs';

test('mock 모드는 결정적 결과를 낸다', async () => {
  const result = await judge({
    appScreenshot: 'irrelevant',
    designScreenshot: 'irrelevant',
    scenariosPath: 'irrelevant',
    mock: true
  });
  expect(result.total).toBeGreaterThan(0);
  expect(result.total).toBeLessThanOrEqual(100);
  for (const axis of ['designQuality', 'originality', 'craft', 'functionality']) {
    expect(typeof result[axis]).toBe('number');
    expect(typeof result.axisNotes[axis]).toBe('string');
  }
});

describe.skipIf(!process.env.JUDGE_SMOKE)('real judge smoke (set JUDGE_SMOKE=1)', () => {
  test('real call returns valid score shape', async () => {
    const out = await judge({
      appScreenshot: 'tests/research-design/fixtures/handoff-stub/index.html',
      designScreenshot: 'tests/research-design/fixtures/handoff-stub/index.html',
      scenariosPath: 'research/2026-05-22-ai-image-vectorization-service/design/scenarios.json',
      mock: false
    });
    expect(out.total).toBeGreaterThan(0);
    for (const ax of ['designQuality', 'originality', 'craft', 'functionality']) {
      expect(out[ax]).toBeGreaterThanOrEqual(0);
      expect(out[ax]).toBeLessThanOrEqual(100);
    }
  }, 240000);
});
