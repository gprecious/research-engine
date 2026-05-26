const relSlugs = (related) => (related ?? []).map(s => String(s).replace(/^\[\[|\]\]$/g, ''));

export function lintVault({ pages }) {
  const findings = [];
  const slugSet = new Set(pages.map(p => p.slug));
  const inbound = new Set();
  for (const p of pages) for (const t of relSlugs(p.frontmatter?.related)) if (slugSet.has(t)) inbound.add(t);

  // title + aliases 를 한 namespace 로 정규화(NFKC+trim+lower) → 교차·대소문자 중복까지 탐지
  const norm = (s) => String(s).normalize('NFKC').trim().toLowerCase();
  const nameToSlugs = {};
  for (const p of pages) {
    const names = [p.frontmatter?.title, ...(p.frontmatter?.aliases ?? [])].filter(Boolean);
    for (const n of new Set(names.map(norm))) (nameToSlugs[n] ??= new Set()).add(p.slug);
  }

  for (const p of pages) {
    const outs = relSlugs(p.frontmatter?.related);
    const sources = p.frontmatter?.sources ?? [];
    const body = String(p.body ?? '');
    const hasClaims = /\S/.test(body.replace(/^#.*$/gm, '').trim());

    if ((!Array.isArray(sources) || sources.length === 0) && hasClaims)
      findings.push({ rule: 'unsourced', slug: p.slug, message: 'sources 비어있음' });

    // citation: 본문 ### research/<slug> 섹션이 모두 frontmatter.sources 안에 있어야 함
    const sectionSrcs = [...body.matchAll(/^### (research\/\S+)/gm)].map(m => m[1]);
    if (/\[\d+\]/.test(body) && (sectionSrcs.length === 0 || sources.length === 0))
      findings.push({ rule: 'citation-unresolved', slug: p.slug, message: '[n] 인용에 대응 섹션/출처 없음' });
    for (const s of sectionSrcs) if (!sources.includes(s))
      findings.push({ rule: 'citation-unresolved', slug: p.slug, message: `섹션 ${s} 가 sources에 없음` });

    for (const t of outs) if (!slugSet.has(t))
      findings.push({ rule: 'broken-link', slug: p.slug, message: `끊긴 링크: [[${t}]]` });

    if (!outs.some(t => slugSet.has(t)) && !inbound.has(p.slug))
      findings.push({ rule: 'orphan', slug: p.slug, message: '인바운드·아웃바운드 링크 없음' });

    const names = [p.frontmatter?.title, ...(p.frontmatter?.aliases ?? [])].filter(Boolean);
    for (const n of new Set(names.map(norm)))
      if (nameToSlugs[n] && nameToSlugs[n].size > 1)
        findings.push({ rule: 'duplicate-name', slug: p.slug, message: `중복 이름(title/alias): ${n}` });
  }
  return { findings };
}

// CLI: node lib/wiki/lint.mjs --vault <dir>
if (import.meta.url === `file://${process.argv[1]}`) {
  const fs = await import('node:fs/promises');
  const path = await import('node:path');
  const { parsePage } = await import('./frontmatter.mjs');
  const get = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
  const vaultDir = get('--vault') ?? path.join(process.cwd(), 'wiki');
  const pages = [];
  for (const [type, dir] of Object.entries({ concept: 'concepts', entity: 'entities' })) {
    let files = [];
    try { files = await fs.readdir(path.join(vaultDir, dir)); } catch { continue; }
    for (const f of files.filter(f => f.endsWith('.md'))) {
      const { frontmatter, body } = parsePage(await fs.readFile(path.join(vaultDir, dir, f), 'utf8'));
      pages.push({ slug: frontmatter.slug ?? f.replace(/\.md$/, ''), type, frontmatter, body });
    }
  }
  process.stdout.write(JSON.stringify(lintVault({ pages }), null, 2) + '\n');
}
