import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { tokenize } from './tokenize.mjs';

async function readJsonOrNull(filePath) {
  try {
    return JSON.parse(await fs.readFile(filePath, 'utf8'));
  } catch {
    return null;
  }
}

async function readFrontmatter(mdPath) {
  try {
    const text = await fs.readFile(mdPath, 'utf8');
    const m = text.match(/^---\n([\s\S]*?)\n---/);
    if (!m) return {};
    const fm = {};
    for (const line of m[1].split('\n')) {
      const kv = line.match(/^(\w+):\s*"?(.*?)"?$/);
      if (kv) fm[kv[1]] = kv[2];
    }
    return fm;
  } catch {
    return {};
  }
}

function extractTopics(readmeText) {
  const topicCandidates = new Set();
  for (const m of readmeText.matchAll(/^###?\s+(.+?)$/gm)) {
    const cleaned = m[1].replace(/\(.*?\)|\[.*?\]|—|—.*$/g, '').trim();
    if (cleaned.length >= 2 && cleaned.length <= 60) topicCandidates.add(cleaned);
  }
  return Array.from(topicCandidates).slice(0, 12);
}

export async function buildSessionEntry(sessionPath) {
  const slug = path.basename(sessionPath);
  const readmePath = path.join(sessionPath, 'README.md');
  const sourcesPath = path.join(sessionPath, 'sources.json');
  const intentPath = path.join(sessionPath, 'intent.json');

  const [sources, intent, fm] = await Promise.all([
    readJsonOrNull(sourcesPath),
    readJsonOrNull(intentPath),
    readFrontmatter(readmePath)
  ]);

  let readmeText = '';
  try { readmeText = await fs.readFile(readmePath, 'utf8'); } catch {}

  // README.md is the authority — always re-hash if present.
  // Falls back to sources.json hash only when README is missing.
  const content_sha256 = readmeText
    ? crypto.createHash('sha256').update(readmeText).digest('hex')
    : (sources?.content_sha256 ?? '');

  const explicitActors = sources?.created_by;
  const created_by = Array.isArray(explicitActors) ? explicitActors : [];

  const purpose = intent?.purpose ?? sources?.intent?.purpose ?? '';
  const focus = intent?.focus ?? sources?.intent?.focus ?? '';
  const audience_level = intent?.audience_level ?? sources?.intent?.audience_level ?? '';

  const bySources = sources?.sources ?? [];
  const by_type = {};
  for (const s of bySources) {
    const t = s.type ?? 'unknown';
    by_type[t] = (by_type[t] ?? 0) + 1;
  }

  return {
    slug,
    path: path.relative(process.cwd(), sessionPath),
    input_type: sources?.input_type ?? fm.input_type ?? 'unknown',
    input: sources?.input ?? '',
    title: fm.title ?? '',
    created: sources?.created ?? fm.created ?? '',
    intent: {
      purpose,
      focus,
      audience_level,
      purpose_tokens: tokenize(`${purpose} ${focus}`)
    },
    sources_summary: { count: bySources.length, by_type },
    topics: extractTopics(readmeText),
    related_count: 0,
    content_sha256,
    created_by,
    notion_url: sources?.output_notion_url ?? '',
    dreamed_in: []
  };
}

export async function buildDreamEntry(dreamPath) {
  const run_id = path.basename(dreamPath);
  const readmePath = path.join(dreamPath, 'README.md');
  await fs.readFile(readmePath, 'utf8');  // throws if missing
  const fm = await readFrontmatter(readmePath);
  let insight_files = [];
  try {
    insight_files = (await fs.readdir(path.join(dreamPath, 'insights')))
      .filter(f => f.endsWith('.md'));
  } catch {}
  return {
    run_id,
    path: path.relative(process.cwd(), dreamPath),
    created: fm.created ?? '',
    status: fm.status ?? 'active',
    supersedes: fm.supersedes && fm.supersedes !== 'null' ? fm.supersedes : null,
    inputs: [],
    insight_files
  };
}

function getGitSha() {
  try {
    return execFileSync('git', ['rev-parse', '--short', 'HEAD'], { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
  } catch {
    return 'unknown';
  }
}

export async function buildManifest({ researchDir, dreamsDir }) {
  const sessions = [];
  const dreams = [];

  try {
    const entries = await fs.readdir(researchDir, { withFileTypes: true });
    for (const e of entries) {
      if (!e.isDirectory() || e.name.startsWith('_')) continue;
      const sessionPath = path.join(researchDir, e.name);
      try {
        const entry = await buildSessionEntry(sessionPath);
        try {
          const rels = await fs.readdir(path.join(sessionPath, 'related'));
          entry.related_count = rels.filter(r => r.endsWith('.md')).length;
        } catch {}
        sessions.push(entry);
      } catch {}
    }
  } catch {}

  try {
    const entries = await fs.readdir(dreamsDir, { withFileTypes: true });
    for (const e of entries) {
      if (!e.isDirectory()) continue;
      const dreamPath = path.join(dreamsDir, e.name);
      try {
        const entry = await buildDreamEntry(dreamPath);
        const drSources = await readJsonOrNull(path.join(dreamPath, 'sources.json'));
        if (drSources?.inputs) entry.inputs = drSources.inputs;
        dreams.push(entry);
        for (const inputSlug of entry.inputs ?? []) {
          const session = sessions.find(s => s.slug === inputSlug);
          if (session && !session.dreamed_in.includes(entry.run_id)) {
            session.dreamed_in.push(entry.run_id);
          }
        }
      } catch {}
    }
  } catch {}

  return {
    version: 1,
    generated_at: new Date().toISOString(),
    generator: `scripts/memory_reindex.sh@${getGitSha()}`,
    sessions,
    dreams
  };
}

// CLI: node manifest_schema.mjs --build --research-dir <path> --dreams-dir <path>
if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  if (args[0] === '--build') {
    const get = (flag) => {
      const i = args.indexOf(flag);
      return i >= 0 ? args[i + 1] : null;
    };
    const manifest = await buildManifest({
      researchDir: get('--research-dir') ?? 'research',
      dreamsDir: get('--dreams-dir') ?? 'docs/dreams'
    });
    process.stdout.write(JSON.stringify(manifest, null, 2) + '\n');
  } else {
    console.error('usage: node manifest_schema.mjs --build --research-dir <path> --dreams-dir <path>');
    process.exit(2);
  }
}
