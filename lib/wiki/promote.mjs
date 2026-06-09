import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyIngest } from './apply.mjs';
import { appendChangeLog } from './changelog.mjs';
import { ensureTags, parsePage, serializePage, validateFrontmatter } from './frontmatter.mjs';
import { appendLog, isIngested, rebuildIndex } from './index_log.mjs';

const DIR = { concept: 'concepts', entity: 'entities', synthesis: 'synthesis', ephemeral: 'ephemeral' };
const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/;

async function readText(file, fallback = '') {
  try { return await fs.readFile(file, 'utf8'); } catch { return fallback; }
}

async function writeAtomic(abs, content) {
  await fs.mkdir(path.dirname(abs), { recursive: true });
  const tmp = `${abs}.tmp-${process.pid}`;
  await fs.writeFile(tmp, content);
  await fs.rename(tmp, abs);
}

function relSlugs(related) {
  return (related ?? []).map((s) => String(s).replace(/^\[\[|\]\]$/g, ''));
}

function parseBody(body) {
  const text = String(body ?? '');
  const tldr = text.match(/## TL;DR\s*\n([\s\S]*?)(?:\n## |$)/)?.[1]?.trim() ?? '';
  const sectionSrcs = [...text.matchAll(/^### (research\/\S+)[ \t]*\n([\s\S]*?)(?=\n### research\/|(?![\s\S]))/gm)];
  const perspectives = Object.fromEntries(sectionSrcs.map((m) => [m[1].trim(), m[2].trim()]));
  return { tldr, perspectives };
}

async function listLivePages(vaultDir) {
  const pages = [];
  for (const [type, dir] of Object.entries(DIR)) {
    let files = [];
    try { files = await fs.readdir(path.join(vaultDir, dir)); } catch { continue; }
    for (const file of files.filter((f) => f.endsWith('.md'))) {
      const raw = await fs.readFile(path.join(vaultDir, dir, file), 'utf8');
      const { frontmatter } = parsePage(raw);
      pages.push({ type, slug: frontmatter.slug ?? file.replace(/\.md$/, ''), title: frontmatter.title ?? '' });
    }
  }
  return pages;
}

async function listDrafts(vaultDir) {
  const drafts = [];
  for (const [type, dir] of Object.entries(DIR)) {
    let files = [];
    const base = path.join(vaultDir, '_drafts', dir);
    try { files = await fs.readdir(base); } catch { continue; }
    for (const file of files.filter((f) => f.endsWith('.md'))) {
      drafts.push({ type, dir, slug: file.replace(/\.md$/, ''), rel: `_drafts/${dir}/${file}`, abs: path.join(base, file) });
    }
  }
  return drafts;
}

async function findDraft(vaultDir, slug) {
  return (await listDrafts(vaultDir)).find((draft) => draft.slug === slug) ?? null;
}

function pagePlanFromDraft(page, date) {
  const { frontmatter, body } = page;
  const parsed = parseBody(body);
  const sources = frontmatter.sources ?? [];
  const source = sources[0];
  if (!source) throw new Error(`draft ${frontmatter.slug}: sources required`);
  return {
    source,
    pages: [{
      type: frontmatter.type,
      title: frontmatter.title,
      slug: frontmatter.slug,
      aliases: frontmatter.aliases ?? [],
      sources,
      confidence: frontmatter.confidence ?? 'medium',
      tldr: parsed.tldr,
      perspective: parsed.perspectives[source] ?? body,
      links: relSlugs(frontmatter.related),
      updated: date,
    }],
  };
}

async function updateIndex(vaultDir) {
  await writeAtomic(path.join(vaultDir, 'index.md'), rebuildIndex(await listLivePages(vaultDir)));
}

async function appendPromoteLogs(vaultDir, date, slug, rel) {
  const logPath = path.join(vaultDir, 'log.md');
  const currentLog = await readText(logPath);
  if (!isIngested(currentLog, slug)) {
    await writeAtomic(logPath, appendLog(currentLog, { date, action: 'promote', slug }));
  }
  const changePath = path.join(vaultDir, 'change_log.md');
  const currentChange = await readText(changePath);
  await writeAtomic(changePath, appendChangeLog(currentChange, { date, kind: 'promote', detail: `${slug} -> ${rel}` }));
}

async function promoteOne(vaultDir, slug, date) {
  if (!SLUG_RE.test(slug)) throw new Error(`slug must be ASCII kebab-case: ${slug}`);
  const draft = await findDraft(vaultDir, slug);
  const live = (await listLivePages(vaultDir)).find((page) => page.slug === slug);
  if (!draft) {
    return live ? { skipped: { slug, reason: 'already-live' } } : { skipped: { slug, reason: 'missing-draft' } };
  }

  const raw = await fs.readFile(draft.abs, 'utf8');
  const parsed = parsePage(raw);
  const frontmatter = ensureTags(parsed.frontmatter);
  const validation = validateFrontmatter(frontmatter);
  if (!validation.ok) throw new Error(`invalid draft frontmatter for ${slug}: ${validation.errors.join('; ')}`);
  if (!DIR[frontmatter.type]) throw new Error(`invalid draft type: ${frontmatter.type}`);
  if (frontmatter.slug !== slug) throw new Error(`draft slug mismatch: ${frontmatter.slug} != ${slug}`);

  const rel = `${DIR[frontmatter.type]}/${slug}.md`;
  const liveAbs = path.join(vaultDir, rel);
  if (!path.resolve(liveAbs).startsWith(path.resolve(vaultDir) + path.sep)) {
    throw new Error(`path escapes vault: ${rel}`);
  }

  const liveExists = await readText(liveAbs, null);
  if (liveExists == null) {
    await writeAtomic(liveAbs, serializePage({ frontmatter, body: parsed.body }));
  } else {
    await applyIngest({ vaultDir, pagePlan: pagePlanFromDraft({ frontmatter, body: parsed.body }, date), date });
  }
  await fs.rm(draft.abs);
  await updateIndex(vaultDir);
  await appendPromoteLogs(vaultDir, date, slug, rel);
  return { promoted: rel };
}

export async function promote({ vaultDir, slugs = [], all = false, date = new Date().toISOString().slice(0, 10) }) {
  const targets = all ? (await listDrafts(vaultDir)).map((draft) => draft.slug) : slugs;
  const promoted = [];
  const skipped = [];
  for (const slug of targets) {
    const result = await promoteOne(vaultDir, slug, date);
    if (result.promoted) promoted.push(result.promoted);
    if (result.skipped) skipped.push(result.skipped);
  }
  return { promoted, skipped };
}

async function runCli() {
  const get = (flag) => {
    const index = process.argv.indexOf(flag);
    return index >= 0 ? process.argv[index + 1] : null;
  };
  const vaultDir = get('--vault') ?? path.join(process.cwd(), 'wiki');
  const date = get('--date') ?? new Date().toISOString().slice(0, 10);
  const all = process.argv.includes('--all');
  const slugArg = get('--slug') ?? process.argv.find((arg, index) => index > 1 && !arg.startsWith('--') && process.argv[index - 1] !== '--vault' && process.argv[index - 1] !== '--date');
  const result = await promote({ vaultDir, all, slugs: all ? [] : [slugArg].filter(Boolean), date });
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await runCli();
}
