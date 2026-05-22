import { test, expect } from 'vitest';
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

test('real 모드는 구현 전까지 throw', async () => {
  await expect(
    judge({ appScreenshot: 'x', designScreenshot: 'x', scenariosPath: 'x', mock: false })
  ).rejects.toThrow(/not implemented/);
});
