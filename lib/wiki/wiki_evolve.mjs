import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

async function readText(file, fallback = '') {
  try { return await fs.readFile(file, 'utf8'); } catch { return fallback; }
}

async function writeAtomic(abs, content) {
  await fs.mkdir(path.dirname(abs), { recursive: true });
  const tmp = `${abs}.tmp-${process.pid}`;
  await fs.writeFile(tmp, content);
  await fs.rename(tmp, abs);
}

function extractRegion(text, region) {
  const re = new RegExp(`<!--\\s*evolvable:${region}\\s*-->\\n([\\s\\S]*?)\\n<!--\\s*/evolvable\\s*-->`);
  const match = text.match(re);
  if (!match) throw new Error(`evolvable region not found: ${region}`);
  return match[1].trim();
}

export async function prepareWikiEvolveInput({ vaultDir, region }) {
  const agents = await readText(path.join(vaultDir, 'AGENTS.md'));
  return {
    target: 'wiki',
    region,
    currentBody: extractRegion(agents, region),
    reflectState: JSON.parse(await readText(path.join(vaultDir, '_index/reflect_state.json'), '{"runs":[]}')),
    changeLog: await readText(path.join(vaultDir, 'change_log.md')),
  };
}

async function appendLedger(vaultDir, entry) {
  const file = path.join(vaultDir, '_index/evolve-ledger.json');
  const current = JSON.parse(await readText(file, '{"entries":[]}'));
  const next = { ...current, entries: [...(current.entries ?? []), entry] };
  await writeAtomic(file, `${JSON.stringify(next, null, 2)}\n`);
}

export async function applyWikiEvolveCandidate({
  vaultDir,
  region,
  candidateBody,
  rationale = '',
  date = new Date().toISOString().slice(0, 10),
}) {
  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(region)) throw new Error(`region must be ASCII kebab-case: ${region}`);
  const rel = `_drafts/_schema/agents-${region}.candidate.md`;
  const body = [
    `# AGENTS ${region} Candidate`,
    '',
    `date: ${date}`,
    `region: ${region}`,
    '',
    '## Rationale',
    rationale,
    '',
    '## Candidate Body',
    '',
    candidateBody,
    '',
  ].join('\n');
  await writeAtomic(path.join(vaultDir, rel), body);
  await appendLedger(vaultDir, { date, region, candidate: rel, rationale });
  return { candidate: rel };
}

async function runCli() {
  const get = (flag) => {
    const index = process.argv.indexOf(flag);
    return index >= 0 ? process.argv[index + 1] : null;
  };
  const vaultDir = get('--vault') ?? path.join(process.cwd(), 'wiki');
  const region = get('--region') ?? 'page-rules';
  if (process.argv.includes('--prepare')) {
    process.stdout.write(`${JSON.stringify(await prepareWikiEvolveInput({ vaultDir, region }), null, 2)}\n`);
    return;
  }
  const mutatorPath = get('--apply-candidate');
  if (!mutatorPath) throw new Error('wiki_evolve: --prepare or --apply-candidate <json> required');
  const mutator = JSON.parse(await fs.readFile(mutatorPath, 'utf8'));
  const variant = mutator.variants?.[0] ?? mutator;
  const result = await applyWikiEvolveCandidate({
    vaultDir,
    region,
    candidateBody: variant.body,
    rationale: variant.rationale ?? '',
    date: get('--date') ?? new Date().toISOString().slice(0, 10),
  });
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await runCli();
}
