import { describe, it, expect } from 'vitest';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { nextVersion, archivePath, archiveCurrent } from './archive.mjs';

describe('archive', () => {
  it('nextVersion increments from history max', () => {
    expect(nextVersion([])).toBe(1);
    expect(nextVersion([{ version: 1 }, { version: 2 }])).toBe(3);
    expect(nextVersion([{ version: 5 }, { version: 2 }])).toBe(6);
  });

  it('archivePath formats agents/archive/<name>.v<N>.md', () => {
    expect(archivePath('agents', 'youtube-adapter', 2)).toBe(
      'agents/archive/youtube-adapter.v2.md'
    );
  });

  it('archiveCurrent copies live file to archive', () => {
    const dir = mkdtempSync(join(tmpdir(), 'evolve-'));
    const agentsDir = join(dir, 'agents');
    const archiveDir = join(agentsDir, 'archive');
    mkdirSync(agentsDir, { recursive: true });
    writeFileSync(join(agentsDir, 'foo.md'), 'live v1\n', { flag: 'w' });
    archiveCurrent({ agentsDir, name: 'foo', version: 1 });
    expect(existsSync(join(archiveDir, 'foo.v1.md'))).toBe(true);
    expect(readFileSync(join(archiveDir, 'foo.v1.md'), 'utf8')).toBe('live v1\n');
    rmSync(dir, { recursive: true });
  });
});
