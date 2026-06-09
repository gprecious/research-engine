import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyIngest } from './apply.mjs';
import { appendChangeLog } from './changelog.mjs';
import { ensureTags, parsePage, serializePage } from './frontmatter.mjs';
import { discoverResearchSlugs, lintVault } from './lint.mjs';

const DIRS = ['concepts', 'entities', 'synthesis', 'ephemeral'];
const AUTO_RULES = new Set(['broken-link', 'duplicate-name', 'stale', 'stale-flag', 'tag-fix', 'raw-coverage']);
const DRAFT_RULES = new Set(['new-page', 'new-link', 'synthesis', 'schema']);

export function classify(findings) {
  const auto = [];
  const draft = [];
  for (const finding of findings ?? []) {
    if (AUTO_RULES.has(finding.rule)) auto.push(finding);
    else if (DRAFT_RULES.has(finding.rule)) draft.push(finding);
  }
  return { auto, draft };
}

async function readText(file, fallback = '') {
  try { return await fs.readFile(file, 'utf8'); } catch { return fallback; }
}

async function writeAtomic(abs, content) {
  await fs.mkdir(path.dirname(abs), { recursive: true });
  const tmp = `${abs}.tmp-${process.pid}`;
  await fs.writeFile(tmp, content);
  await fs.rename(tmp, abs);
}

async function listPages(vaultDir) {
  const pages = [];
  for (const dir of DIRS) {
    let files = [];
    try { files = await fs.readdir(path.join(vaultDir, dir)); } catch { continue; }
    for (const file of files.filter((f) => f.endsWith('.md'))) {
      const rel = `${dir}/${file}`;
      const raw = await fs.readFile(path.join(vaultDir, rel), 'utf8');
      const { frontmatter, body } = parsePage(raw);
      pages.push({
        rel,
        abs: path.join(vaultDir, rel),
        type: frontmatter.type ?? dir.replace(/s$/, ''),
        slug: frontmatter.slug ?? file.replace(/\.md$/, ''),
        frontmatter,
        body,
      });
    }
  }
  return pages;
}

async function findPage(vaultDir, slug) {
  return (await listPages(vaultDir)).find((page) => page.slug === slug) ?? null;
}

function targetFromFinding(finding) {
  if (finding.target) return finding.target;
  const match = String(finding.message ?? '').match(/\[\[([^\]]+)\]\]/);
  return match?.[1] ?? null;
}

async function appendVaultChange(vaultDir, entry) {
  const file = path.join(vaultDir, 'change_log.md');
  const current = await readText(file);
  await writeAtomic(file, appendChangeLog(current, entry));
}

function applyBudget(items, budget) {
  const limit = Number.isFinite(Number(budget)) ? Math.max(0, Number(budget)) : items.length;
  return items.slice(0, limit);
}

async function applyAutoFinding(vaultDir, finding, date) {
  if (finding.rule === 'raw-coverage') {
    const slug = String(finding.slug).replace(/^research\//, '');
    const todoPath = path.join(vaultDir, '_todos', `${slug}.md`);
    await writeAtomic(todoPath, `# Research coverage gap: ${finding.slug}\n\n- Source not ingested: ${finding.slug}\n`);
    await appendVaultChange(vaultDir, { date, kind: 'coverage-todo', detail: `${finding.slug} -> _todos/${slug}.md` });
    return { rule: finding.rule, slug: finding.slug, action: 'todo' };
  }

  if (finding.rule === 'duplicate-name') {
    await appendVaultChange(vaultDir, { date, kind: 'duplicate-name', detail: `${finding.slug}` });
    return { rule: finding.rule, slug: finding.slug, action: 'logged' };
  }

  const page = await findPage(vaultDir, finding.slug);
  if (!page) return { rule: finding.rule, slug: finding.slug, action: 'missing' };

  let frontmatter = { ...page.frontmatter };
  let body = page.body;
  let kind = finding.rule;
  let detail = finding.slug;

  if (finding.rule === 'broken-link') {
    const target = targetFromFinding(finding);
    frontmatter.related = (frontmatter.related ?? []).filter((link) => String(link).replace(/^\[\[|\]\]$/g, '') !== target);
    body = body.split('\n').filter((line) => line.trim() !== `- [[${target}]]`).join('\n');
    detail = `${finding.slug} removed [[${target}]]`;
  } else if (finding.rule === 'tag-fix') {
    frontmatter = ensureTags(frontmatter);
    detail = `${finding.slug} tags`;
  } else if (finding.rule === 'stale' || finding.rule === 'stale-flag') {
    frontmatter.status = 'stale';
    kind = 'stale-flag';
    detail = `${finding.slug} status: stale`;
  }

  await writeAtomic(page.abs, serializePage({ frontmatter: ensureTags(frontmatter), body }));
  await appendVaultChange(vaultDir, { date, kind, detail });
  return { rule: finding.rule, slug: finding.slug, action: 'updated' };
}

async function writeReport(vaultDir, date, entries) {
  const report = [
    `# Librarian Report ${date}`,
    '',
    ...entries.map((entry) => `- ${entry.rule ?? entry.action}: ${entry.slug ?? entry.detail ?? ''}`),
    '',
  ].join('\n');
  const rel = `outputs/librarian-${date}.md`;
  await writeAtomic(path.join(vaultDir, rel), report);
  return rel;
}

export async function applyTier({ vaultDir, plan, tier, budget = Infinity }) {
  const date = plan?.date ?? new Date().toISOString().slice(0, 10);
  const items = applyBudget(plan?.[tier] ?? [], budget);

  if (tier === 'auto') {
    const applied = [];
    for (const finding of items) applied.push(await applyAutoFinding(vaultDir, finding, date));
    const report = await writeReport(vaultDir, date, applied);
    return { tier, applied, report };
  }

  if (tier === 'draft') {
    const drafted = [];
    for (const item of items) {
      if (!item.pagePlan) continue;
      const result = await applyIngest({ vaultDir, pagePlan: item.pagePlan, date, draft: true });
      drafted.push(...result.created, ...result.merged);
    }
    const report = await writeReport(vaultDir, date, items);
    return { tier, drafted, report };
  }

  throw new Error(`unknown tier: ${tier}`);
}

async function loadOptionalPlan(vaultDir) {
  const raw = await readText(path.join(vaultDir, '_index', 'librarian-plan.json'), '');
  return raw ? JSON.parse(raw) : {};
}

async function runCli() {
  const get = (flag) => {
    const index = process.argv.indexOf(flag);
    return index >= 0 ? process.argv[index + 1] : null;
  };
  const vaultDir = get('--vault') ?? path.join(process.cwd(), 'wiki');
  const date = get('--date') ?? new Date().toISOString().slice(0, 10);
  const budget = Number(get('--budget') ?? Infinity);
  const pages = await listPages(vaultDir);
  const logText = await readText(path.join(vaultDir, 'log.md'));
  const findings = lintVault({ pages, now: date, researchSlugs: await discoverResearchSlugs(process.cwd()), logText }).findings;
  const classification = classify(findings);

  if (process.argv.includes('--report') || !process.argv.includes('--apply')) {
    process.stdout.write(`${JSON.stringify({ findings, classification }, null, 2)}\n`);
    return;
  }

  const proposalPlan = await loadOptionalPlan(vaultDir);
  const plan = {
    date,
    auto: [...classification.auto, ...(proposalPlan.auto ?? [])],
    draft: [...classification.draft, ...(proposalPlan.draft ?? [])],
  };
  const auto = await applyTier({ vaultDir, plan, tier: 'auto', budget });
  const draft = await applyTier({ vaultDir, plan, tier: 'draft', budget });
  process.stdout.write(`${JSON.stringify({ findings, classification, auto, draft }, null, 2)}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await runCli();
}
