import YAML from 'yaml';

const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/; // ASCII kebab only

export function parsePage(raw) {
  const text = String(raw ?? '');
  const m = text.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
  if (!m) return { frontmatter: {}, body: text };
  return { frontmatter: YAML.parse(m[1]) ?? {}, body: m[2] ?? '' };
}

export function serializePage({ frontmatter, body }) {
  const yaml = YAML.stringify(frontmatter).trimEnd();
  return `---\n${yaml}\n---\n\n${String(body ?? '').trim()}\n`;
}

export function validateFrontmatter(fm) {
  const errors = [];
  if (fm?.type !== 'concept' && fm?.type !== 'entity') errors.push('type must be concept|entity');
  if (!fm?.title || typeof fm.title !== 'string') errors.push('title required');
  if (!fm?.slug || !SLUG_RE.test(fm.slug)) errors.push('slug must be ASCII kebab-case');
  if (!Array.isArray(fm?.sources)) errors.push('sources must be an array');
  if (!Array.isArray(fm?.related)) errors.push('related must be an array');
  if (fm?.aliases != null && !Array.isArray(fm.aliases)) errors.push('aliases must be an array');
  if (fm?.confidence != null && !['high', 'medium', 'low'].includes(fm.confidence)) errors.push('confidence must be high|medium|low');
  if (!fm?.created) errors.push('created required');
  if (!fm?.updated) errors.push('updated required');
  return { ok: errors.length === 0, errors };
}
