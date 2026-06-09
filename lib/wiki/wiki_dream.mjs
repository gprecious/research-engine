import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ensureTags, parsePage, serializePage } from './frontmatter.mjs';

const LIVE_DIRS = { concepts: 'concept', entities: 'entity' };

async function readText(file, fallback = '') {
  try { return await fs.readFile(file, 'utf8'); } catch { return fallback; }
}

async function writeAtomic(abs, content) {
  await fs.mkdir(path.dirname(abs), { recursive: true });
  const tmp = `${abs}.tmp-${process.pid}`;
  await fs.writeFile(tmp, content);
  await fs.rename(tmp, abs);
}

function tldr(body) {
  return String(body ?? '').match(/## TL;DR\s*\n([\s\S]*?)(?:\n## |$)/)?.[1]?.trim() ?? '';
}

export async function collectWikiCorpus({ vaultDir }) {
  const corpus = [];
  for (const [dir, fallbackType] of Object.entries(LIVE_DIRS)) {
    let files = [];
    try { files = await fs.readdir(path.join(vaultDir, dir)); } catch { continue; }
    for (const file of files.filter((name) => name.endsWith('.md'))) {
      const raw = await fs.readFile(path.join(vaultDir, dir, file), 'utf8');
      const { frontmatter, body } = parsePage(raw);
      corpus.push({
        type: frontmatter.type ?? fallbackType,
        slug: frontmatter.slug ?? file.replace(/\.md$/, ''),
        title: frontmatter.title ?? '',
        sources: frontmatter.sources ?? [],
        related: frontmatter.related ?? [],
        summary: tldr(body),
      });
    }
  }
  return corpus;
}

async function appendReflectState(vaultDir, entry) {
  const file = path.join(vaultDir, '_index', 'reflect_state.json');
  const current = JSON.parse(await readText(file, '{"runs":[]}'));
  const next = { ...current, runs: [...(current.runs ?? []), entry] };
  await writeAtomic(file, `${JSON.stringify(next, null, 2)}\n`);
}

function validateSynthesis(input) {
  if (!input?.slug || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(input.slug)) throw new Error('synthesis slug must be ASCII kebab-case');
  if ((input.evidenceSlugs ?? []).length < 2) throw new Error('synthesis requires at least 2 evidence slugs');
}

export async function applyWikiDream({ vaultDir, synthesis, todo, date = new Date().toISOString().slice(0, 10) }) {
  validateSynthesis(synthesis);
  const frontmatter = ensureTags({
    type: 'synthesis',
    title: synthesis.title,
    slug: synthesis.slug,
    aliases: [],
    sources: synthesis.sources ?? [],
    related: synthesis.evidenceSlugs.map((slug) => `[[${slug}]]`),
    confidence: synthesis.confidence ?? 'medium',
    created: date,
    updated: date,
  });
  const body = [
    '## TL;DR',
    synthesis.summary ?? '',
    '',
    '## Evidence pages',
    ...synthesis.evidenceSlugs.map((slug) => `- [[${slug}]]`),
    '',
    '## 출처별 관점',
    '',
    ...(synthesis.sources ?? []).map((source) => `### ${source}\n- ${synthesis.summary ?? synthesis.title} [1]`),
    '',
  ].join('\n');
  const synthesisRel = `_drafts/synthesis/${synthesis.slug}.md`;
  await writeAtomic(path.join(vaultDir, synthesisRel), serializePage({ frontmatter, body }));

  let todoRel = null;
  if (todo?.slug) {
    if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(todo.slug)) throw new Error('todo slug must be ASCII kebab-case');
    todoRel = `_todos/${todo.slug}.md`;
    await writeAtomic(path.join(vaultDir, todoRel), `# ${todo.title ?? todo.slug}\n\n${todo.question ?? ''}\n`);
  }

  await appendReflectState(vaultDir, {
    date,
    synthesis: synthesis.slug,
    evidenceSlugs: synthesis.evidenceSlugs,
    todo: todo?.slug ?? null,
  });
  return { synthesis: synthesisRel, todo: todoRel };
}

async function runCli() {
  const get = (flag) => {
    const index = process.argv.indexOf(flag);
    return index >= 0 ? process.argv[index + 1] : null;
  };
  const vaultDir = get('--vault') ?? path.join(process.cwd(), 'wiki');
  if (process.argv.includes('--corpus')) {
    process.stdout.write(`${JSON.stringify(await collectWikiCorpus({ vaultDir }), null, 2)}\n`);
    return;
  }
  const inputPath = get('--apply');
  if (!inputPath) throw new Error('wiki_dream: --corpus or --apply <json> required');
  const input = JSON.parse(await fs.readFile(inputPath, 'utf8'));
  const result = await applyWikiDream({
    vaultDir,
    synthesis: input.synthesis,
    todo: input.todo,
    date: get('--date') ?? new Date().toISOString().slice(0, 10),
  });
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await runCli();
}
