import { test, expect } from 'vitest';
import { mkdtempSync, existsSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { scaffoldApp } from '../../../lib/app_scaffold.mjs';
import { parseHandoff } from '../../../lib/design_handoff_parser.mjs';

test('스캐폴드가 Next.js 14 app router 구조를 만든다', () => {
  const dir = mkdtempSync(join(tmpdir(), 'scaffold-'));
  try {
    const handoff = parseHandoff('tests/research-design/fixtures/handoff-stub');
    scaffoldApp({ outDir: dir, handoff, slug: 'fake-slug', title: 'Fake' });
    expect(existsSync(join(dir, 'package.json'))).toBe(true);
    expect(existsSync(join(dir, 'next.config.mjs'))).toBe(true);
    expect(existsSync(join(dir, 'app/layout.tsx'))).toBe(true);
    expect(existsSync(join(dir, 'app/page.tsx'))).toBe(true);
    expect(existsSync(join(dir, 'app/upload/page.tsx'))).toBe(true);
    expect(existsSync(join(dir, 'app/health/route.ts'))).toBe(true);
    expect(existsSync(join(dir, 'public/sample-handoff.html'))).toBe(true);
    expect(existsSync(join(dir, 'app/globals.css'))).toBe(true);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
