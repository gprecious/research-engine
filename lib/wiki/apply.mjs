import fs from 'node:fs/promises';
import path from 'node:path';
import { ensureTags, parsePage, serializePage, validateFrontmatter } from './frontmatter.mjs';
import { rebuildIndex, appendLog, isIngested } from './index_log.mjs';

const DIR = { concept: 'concepts', entity: 'entities' };
const uniq = (a) => [...new Set(a)];
const relSlugs = (related) => (related ?? []).map(s => String(s).replace(/^\[\[|\]\]$/g, ''));

function parseBody(body) {
  const text = String(body ?? '');
  const tldrM = text.match(/## TL;DR\s*\n([\s\S]*?)(?:\n## |$)/);
  const tldr = tldrM ? tldrM[1].trim() : '';
  const perspectives = {};
  const persBlock = text.match(/## 출처별 관점\s*\n([\s\S]*?)(?:\n## 관련 개념|$)/);
  if (persBlock) {
    // source heading(^### research/...)만 매칭 — perspective 내부 하위 heading 오염 방지.
    // 종료 lookahead는 (?![\s\S])(=문자열 끝)을 쓴다. m 플래그의 $ 는 줄끝마다 매칭돼
    // lazy 본문을 첫 줄에서 절단하는 회귀가 있으므로 $ 를 쓰지 않는다.
    const re = /^### (research\/\S+)[ \t]*\n([\s\S]*?)(?=\n### research\/|(?![\s\S]))/gm;
    let m;
    while ((m = re.exec(persBlock[1])) !== null) perspectives[m[1].trim()] = m[2].trim();
  }
  return { tldr, perspectives };
}

function renderBody({ tldr, perspectives, relatedSlugs }) {
  const pers = Object.entries(perspectives)
    .map(([src, txt]) => `### ${src}\n${txt.trim()}`).join('\n\n');
  let out = `## TL;DR\n${(tldr ?? '').trim()}\n\n## 출처별 관점\n\n${pers}\n`;
  if (relatedSlugs.length) out += `\n## 관련 개념\n\n${relatedSlugs.map(s => `- [[${s}]]`).join('\n')}\n`;
  return out;
}

async function listPages(vaultDir) {
  const out = [];
  for (const [type, dir] of Object.entries(DIR)) {
    let files = [];
    try { files = await fs.readdir(path.join(vaultDir, dir)); } catch { continue; }
    for (const f of files.filter(f => f.endsWith('.md'))) {
      const { frontmatter } = parsePage(await fs.readFile(path.join(vaultDir, dir, f), 'utf8'));
      out.push({ type, slug: frontmatter.slug ?? f.replace(/\.md$/, ''), title: frontmatter.title ?? '' });
    }
  }
  return out;
}

async function writeAtomic(abs, content) {
  const tmp = `${abs}.tmp-${process.pid}`;
  await fs.writeFile(tmp, content);
  await fs.rename(tmp, abs); // rename = 원자적 교체 (부분쓰기 방지)
}

export async function applyIngest({ vaultDir, pagePlan, date }) {
  // 1) 검증·준비 전체 (디스크 쓰기 전)
  const prepared = [];
  for (const p of pagePlan.pages) {
    // 불변식: 이번 세션(pagePlan.source)은 반드시 page.sources 에 포함
    if (!(p.sources ?? []).includes(pagePlan.source))
      throw new Error(`page ${p.slug}: sources must include pagePlan.source (${pagePlan.source})`);
    // 경로 탈출 방지: p.type·p.slug 를 path.join 전에 검증 (merge 경로 포함)
    if (p.type !== 'concept' && p.type !== 'entity')
      throw new Error(`page ${p.slug}: invalid type (${p.type})`);
    if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(p.slug ?? ''))
      throw new Error(`page slug must be ASCII kebab-case: ${p.slug}`);
    const rel = `${DIR[p.type]}/${p.slug}.md`;
    const abs = path.join(vaultDir, rel);
    if (!path.resolve(abs).startsWith(path.resolve(vaultDir) + path.sep))
      throw new Error(`path escapes vault: ${rel}`);
    let existing = null;
    try { existing = parsePage(await fs.readFile(abs, 'utf8')); } catch {}

    // links 는 soft-link 허용(미존재 페이지 = 향후 생성 대상; lint 가 broken-link 로 표시)
    const relatedSlugs = uniq([
      ...(existing ? relSlugs(existing.frontmatter.related) : []),
      ...(p.links ?? []),
    ]);
    const fm = existing
      ? { ...existing.frontmatter,
          sources: uniq([...(existing.frontmatter.sources ?? []), ...(p.sources ?? [])]),
          aliases: uniq([...(existing.frontmatter.aliases ?? []), ...(p.aliases ?? [])]),
          related: relatedSlugs.map(s => `[[${s}]]`),
          confidence: p.confidence ?? existing.frontmatter.confidence ?? 'medium',
          updated: date }
      : { type: p.type, title: p.title, slug: p.slug,
          aliases: uniq(p.aliases ?? []), sources: uniq(p.sources ?? []),
          related: relatedSlugs.map(s => `[[${s}]]`),
          confidence: p.confidence ?? 'medium', created: date, updated: date };
    const fmTagged = ensureTags(fm);

    const v = validateFrontmatter(fmTagged);
    if (!v.ok) throw new Error(`invalid frontmatter for ${p.slug}: ${v.errors.join('; ')}`);

    const prev = existing ? parseBody(existing.body) : { tldr: '', perspectives: {} };
    const tldr = prev.tldr || p.tldr || '';
    const perspectives = { ...prev.perspectives };
    // 섹션 키 = 지금 ingest 중인 세션(pagePlan.source). 누적 sources[0] 오기록 방지(claude#1).
    if (p.perspective !== undefined) perspectives[pagePlan.source] = p.perspective;
    const body = renderBody({ tldr, perspectives, relatedSlugs });
    prepared.push({ abs, rel, fm: fmTagged, body, isNew: !existing });
  }

  // 2) 전부 검증 통과 후에만 쓰기 (tmp+rename 원자 교체)
  const created = [], merged = [];
  for (const pr of prepared) {
    await fs.mkdir(path.dirname(pr.abs), { recursive: true });
    await writeAtomic(pr.abs, serializePage({ frontmatter: pr.fm, body: pr.body }));
    (pr.isNew ? created : merged).push(pr.rel);
  }

  // 3) index 재생성 (tmp+rename)
  await writeAtomic(path.join(vaultDir, 'index.md'), rebuildIndex(await listPages(vaultDir)));

  // 4) log 1회 (정확매칭 dedupe, tmp+rename)
  const logPath = path.join(vaultDir, 'log.md');
  let log = ''; try { log = await fs.readFile(logPath, 'utf8'); } catch {}
  if (!isIngested(log, pagePlan.source))
    await writeAtomic(logPath, appendLog(log, { date, action: 'ingest', slug: pagePlan.source }));

  return { source: pagePlan.source, created, merged };
}

// CLI: node lib/wiki/apply.mjs --vault <dir> --plan <plan.json> --date <YYYY-MM-DD>
if (import.meta.url === `file://${process.argv[1]}`) {
  const get = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
  const pagePlan = JSON.parse(await fs.readFile(get('--plan'), 'utf8'));
  const r = await applyIngest({ vaultDir: get('--vault'), pagePlan, date: get('--date') ?? new Date().toISOString().slice(0, 10) });
  process.stdout.write(JSON.stringify(r) + '\n');
}
