import { test, expect } from 'vitest';
import { parseHandoff } from '../../../lib/design_handoff_parser.mjs';

const FIXTURE = 'tests/research-design/fixtures/handoff-stub';

test('파서가 메타를 읽는다', () => {
  const out = parseHandoff(FIXTURE);
  expect(out.meta.tool).toBe('claude.ai/design');
  expect(out.meta.title).toBe('AI Image Vectorization');
});

test('파서가 HTML 페이지를 수집한다', () => {
  const out = parseHandoff(FIXTURE);
  const names = out.pages.map((p) => p.name).sort();
  expect(names).toEqual(['index.html']);
  expect(out.pages[0].html).toContain('data-component="hero"');
});

test('파서가 CSS 를 수집한다', () => {
  const out = parseHandoff(FIXTURE);
  const names = out.styles.map((s) => s.name).sort();
  expect(names).toEqual(['styles.css']);
});

test('파서가 디자인 시스템과 컴포넌트 목록을 노출한다', () => {
  const out = parseHandoff(FIXTURE);
  expect(out.designSystem.colors.accent).toBe('#6c4cff');
  expect(out.components.sort()).toEqual(['hero', 'upload']);
});
