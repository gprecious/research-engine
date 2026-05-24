import { describe, it, expect } from 'vitest';
import { buildSessionEntry, buildDreamEntry, buildManifest } from './manifest_schema.mjs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtureBase = path.resolve(__dirname, '..', '..', 'tests', 'research-engine', 'fixtures', 'memory');

describe('buildSessionEntry', () => {
  it('legacy 세션(content_sha256 부재)을 derived 모드로 빌드', async () => {
    const sessionPath = path.join(fixtureBase, 'legacy-no-hash', 'research', '2026-04-01-legacy-fixture');
    const entry = await buildSessionEntry(sessionPath);

    expect(entry.slug).toBe('2026-04-01-legacy-fixture');
    expect(entry.input_type).toBe('youtube');
    expect(entry.content_sha256).toMatch(/^[0-9a-f]{64}$/);
    expect(entry.created_by).toEqual([]);
    expect(entry.intent.purpose_tokens).toContain('테스트');
    expect(entry.sources_summary.count).toBe(1);
    expect(entry.sources_summary.by_type['youtube-captions']).toBe(1);
    expect(entry.dreamed_in).toEqual([]);
  });
});

describe('buildDreamEntry', () => {
  it('존재하지 않는 dream 경로 → reject', async () => {
    const dreamPath = path.join(fixtureBase, 'no-such-dream');
    await expect(buildDreamEntry(dreamPath)).rejects.toThrow();
  });
});

describe('buildManifest', () => {
  it('빈 research/ + 빈 dreams/ → 빈 sessions·dreams', async () => {
    const researchDir = path.join(fixtureBase, 'manifest-empty', 'research');
    const dreamsDir = path.join(fixtureBase, 'manifest-empty', 'docs', 'dreams');
    const manifest = await buildManifest({ researchDir, dreamsDir });

    expect(manifest.version).toBe(1);
    expect(manifest.sessions).toEqual([]);
    expect(manifest.dreams).toEqual([]);
    expect(manifest.generator).toMatch(/memory_reindex\.sh/);
  });

  it('legacy fixture → 1 session, 0 dream', async () => {
    const researchDir = path.join(fixtureBase, 'legacy-no-hash', 'research');
    const dreamsDir = path.join(fixtureBase, 'manifest-empty', 'docs', 'dreams');
    const manifest = await buildManifest({ researchDir, dreamsDir });
    expect(manifest.sessions.length).toBe(1);
    expect(manifest.dreams.length).toBe(0);
  });
});
