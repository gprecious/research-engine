import { describe, it, expect } from 'vitest';
import { buildSessionEntry, buildDreamEntry, buildManifest } from './manifest_schema.mjs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs/promises';
import os from 'node:os';
import crypto from 'node:crypto';

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

  it('sources.json content_sha256이 README와 어긋나면 README 재해시 우선 (self-healing)', async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'manifest-test-'));
    try {
      const readmeContent = '# Real README content\n\nfresh body\n';
      await fs.writeFile(path.join(tmp, 'README.md'), readmeContent);
      await fs.writeFile(path.join(tmp, 'sources.json'), JSON.stringify({
        content_sha256: 'stale-hash-placeholder',
        input_type: 'youtube',
        sources: []
      }));

      const entry = await buildSessionEntry(tmp);
      const expectedHash = crypto.createHash('sha256').update(readmeContent).digest('hex');
      expect(entry.content_sha256).toBe(expectedHash);
      expect(entry.content_sha256).not.toBe('stale-hash-placeholder');
    } finally {
      await fs.rm(tmp, { recursive: true });
    }
  });

  it('README 없으면 sources.json content_sha256를 fallback (legacy 호환)', async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), 'manifest-test-'));
    try {
      await fs.writeFile(path.join(tmp, 'sources.json'), JSON.stringify({
        content_sha256: 'fallback-hash',
        input_type: 'youtube',
        sources: []
      }));

      const entry = await buildSessionEntry(tmp);
      expect(entry.content_sha256).toBe('fallback-hash');
    } finally {
      await fs.rm(tmp, { recursive: true });
    }
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
