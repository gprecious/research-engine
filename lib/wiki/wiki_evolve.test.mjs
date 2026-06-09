import { describe, it, expect, beforeEach } from 'vitest';
import { execFile } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import { prepareWikiEvolveInput, applyWikiEvolveCandidate } from './wiki_evolve.mjs';

const execFileAsync = promisify(execFile);

let vault;
beforeEach(async () => {
  vault = await fs.mkdtemp(path.join(os.tmpdir(), 'wiki-evolve-'));
  await fs.mkdir(path.join(vault, '_index'), { recursive: true });
  await fs.writeFile(path.join(vault, 'AGENTS.md'), [
    '# Wiki Constitution',
    '',
    '<!-- evolvable:page-rules -->',
    'old rules',
    '<!-- /evolvable -->',
    '',
  ].join('\n'));
});

describe('prepareWikiEvolveInput', () => {
  it('AGENTS.md evolvable region 과 reflect/lint 신호를 준비한다', async () => {
    await fs.writeFile(path.join(vault, '_index/reflect_state.json'), JSON.stringify({ runs: [{ synthesis: 'synth' }] }));
    await fs.writeFile(path.join(vault, 'change_log.md'), '- [2026-06-09] broken-link | a removed [[ghost]]\n');

    const input = await prepareWikiEvolveInput({ vaultDir: vault, region: 'page-rules' });

    expect(input.region).toBe('page-rules');
    expect(input.currentBody).toBe('old rules');
    expect(input.reflectState.runs[0].synthesis).toBe('synth');
    expect(input.changeLog).toMatch(/broken-link/);
  });
});

describe('applyWikiEvolveCandidate', () => {
  it('candidate 와 evolve-ledger 를 쓰고 live AGENTS.md 는 보존한다', async () => {
    const before = await fs.readFile(path.join(vault, 'AGENTS.md'), 'utf8');

    const result = await applyWikiEvolveCandidate({
      vaultDir: vault,
      region: 'page-rules',
      candidateBody: 'new rules',
      rationale: '반복 broken-link 완화',
      date: '2026-06-09',
    });

    expect(result.candidate).toBe('_drafts/_schema/agents-page-rules.candidate.md');
    await expect(fs.readFile(path.join(vault, result.candidate), 'utf8')).resolves.toMatch(/new rules/);
    expect(await fs.readFile(path.join(vault, 'AGENTS.md'), 'utf8')).toBe(before);
    const ledger = JSON.parse(await fs.readFile(path.join(vault, '_index/evolve-ledger.json'), 'utf8'));
    expect(ledger.entries).toHaveLength(1);
    expect(ledger.entries[0]).toMatchObject({ region: 'page-rules', candidate: result.candidate });
  });

  it('CLI apply-candidate 는 candidate 경로 JSON 을 출력한다', async () => {
    const inputPath = path.join(vault, 'mutator.json');
    await fs.writeFile(inputPath, JSON.stringify({ variants: [{ body: 'cli rules', rationale: 'cli' }] }));

    const { stdout } = await execFileAsync(process.execPath, [
      path.join(process.cwd(), 'lib/wiki/wiki_evolve.mjs'),
      '--vault', vault,
      '--apply-candidate', inputPath,
      '--region', 'page-rules',
      '--date', '2026-06-09',
    ]);

    expect(JSON.parse(stdout).candidate).toBe('_drafts/_schema/agents-page-rules.candidate.md');
  });
});
