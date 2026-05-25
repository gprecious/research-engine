import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const prepareScript = resolve(__dirname, 'prepare.mjs');

let work;

beforeAll(() => {
  work = mkdtempSync(`${tmpdir()}/prepare-test-`);
  // dream with README.md + two insight files
  const insightsDir = `${work}/docs/dreams/drm_test/insights`;
  mkdirSync(insightsDir, { recursive: true });
  writeFileSync(`${work}/docs/dreams/drm_test/README.md`, '# dream TOC\n- pattern-a\n- pattern-b\n');
  writeFileSync(`${insightsDir}/pattern-a.md`, '# pattern a\nbody-a-content\n');
  writeFileSync(`${insightsDir}/pattern-b.md`, '# pattern b\nbody-b-content\n');
  // a non-pattern file that must be ignored
  writeFileSync(`${insightsDir}/notes.md`, 'ignore me\n');

  // agent with an evolvable region
  mkdirSync(`${work}/agents`, { recursive: true });
  writeFileSync(
    `${work}/agents/foo.md`,
    '# foo\n<!-- evolvable:bar -->\nhello\n<!-- /evolvable -->\n'
  );
});

afterAll(() => {
  rmSync(work, { recursive: true, force: true });
});

describe('prepare.mjs', () => {
  it('includes insight bodies for each dream, not just the README', () => {
    const out = execFileSync(
      'node',
      [prepareScript, `${work}/agents/foo.md`, 'bar', '--dreams-dir', `${work}/docs/dreams`],
      { encoding: 'utf8' }
    );
    const parsed = JSON.parse(out);

    expect(parsed.region_id).toBe('bar');
    expect(parsed.current_body).toBe('hello');
    expect(parsed.dream_excerpts).toHaveLength(1);

    const dream = parsed.dream_excerpts[0];
    expect(dream.run_id).toBe('drm_test');
    expect(dream.readme).toContain('dream TOC');

    expect(dream.insights).toHaveLength(2);
    expect(dream.insights.map((i) => i.name)).toEqual(['pattern-a', 'pattern-b']);
    expect(dream.insights[0].body).toContain('body-a-content');
    expect(dream.insights[1].body).toContain('body-b-content');
  });
});
