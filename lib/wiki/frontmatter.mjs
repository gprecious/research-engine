// Dependency-free YAML frontmatter for LLM-Wiki pages.
//
// LLM-Wiki page frontmatter is a fixed, flat shape (see validateFrontmatter):
// string scalars and arrays of strings only — no nesting, numbers, or block
// scalars. Hand-rolling parse/serialize for exactly this subset removes the
// runtime dependency on the `yaml` package, which is NOT available when the
// plugin is installed via `git clone` (node_modules is gitignored and nothing
// runs `npm install`). That gap previously made `apply.mjs` / `report_mirror.mjs`
// crash with ERR_MODULE_NOT_FOUND, silently aborting wiki auto-ingest.

const SLUG_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/; // ASCII kebab only
const REQUIRED_TAGS = ['ai-generated', 'llm-wiki'];
const TYPES = ['concept', 'entity', 'synthesis', 'ephemeral'];

// Reserved plain tokens / numerics that YAML would otherwise parse as a
// non-string; we double-quote them on output to keep them strings.
const RESERVED_RE = /^(?:true|false|null|~|yes|no|on|off)$/i;
const NUMERIC_RE = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/;
// Leading characters that make a plain scalar ambiguous in YAML block context.
const LEADING_INDICATOR_RE = /^[\s\-?:,[\]{}#&*!|>'"%@`]/;

function needsQuote(s) {
  if (s === '') return true;
  if (LEADING_INDICATOR_RE.test(s)) return true;
  if (/:\s/.test(s) || /\s#/.test(s)) return true; // "key: value" / " # comment" ambiguity
  if (/[\s:]$/.test(s)) return true; // trailing space or colon
  if (RESERVED_RE.test(s) || NUMERIC_RE.test(s)) return true;
  return false;
}

function emitScalar(value) {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  const s = String(value);
  if (!needsQuote(s)) return s;
  return `"${s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n')}"`;
}

function parseScalar(token) {
  const t = token.trim();
  if (t === '' || t === '~' || t === 'null') return null;
  if (t === '[]') return [];
  if (t.length >= 2 && t[0] === '"' && t[t.length - 1] === '"') {
    try {
      return JSON.parse(t);
    } catch {
      return t.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, '\\').replace(/\\n/g, '\n');
    }
  }
  if (t.length >= 2 && t[0] === "'" && t[t.length - 1] === "'") {
    return t.slice(1, -1).replace(/''/g, "'"); // YAML single-quote escaping
  }
  return t; // plain scalar → string (page schema carries no bare numbers/bools)
}

function parseFrontmatter(src) {
  const out = {};
  const lines = String(src).split('\n');
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) {
      i++;
      continue;
    }
    const m = line.match(/^([A-Za-z0-9_-]+):(.*)$/);
    if (!m) {
      i++;
      continue;
    }
    const key = m[1];
    const rest = m[2].trim();
    if (rest === '') {
      // Either an empty value or a block sequence on the following indented lines.
      const items = [];
      let j = i + 1;
      while (j < lines.length && /^\s+-(?:\s|$)/.test(lines[j])) {
        items.push(parseScalar(lines[j].replace(/^\s+-\s?/, '')));
        j++;
      }
      if (j > i + 1) {
        out[key] = items;
        i = j;
        continue;
      }
      out[key] = null;
      i++;
      continue;
    }
    out[key] = parseScalar(rest);
    i++;
  }
  return out;
}

function serializeFrontmatter(fm) {
  const lines = [];
  for (const [key, value] of Object.entries(fm)) {
    if (Array.isArray(value)) {
      if (value.length === 0) {
        lines.push(`${key}: []`);
        continue;
      }
      lines.push(`${key}:`);
      for (const item of value) lines.push(`  - ${emitScalar(item)}`);
    } else {
      lines.push(`${key}: ${emitScalar(value)}`);
    }
  }
  return lines.join('\n');
}

export function parsePage(raw) {
  const text = String(raw ?? '');
  const m = text.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
  if (!m) return { frontmatter: {}, body: text };
  return { frontmatter: parseFrontmatter(m[1]) ?? {}, body: m[2] ?? '' };
}

export function serializePage({ frontmatter, body }) {
  const yaml = serializeFrontmatter(frontmatter).trimEnd();
  return `---\n${yaml}\n---\n\n${String(body ?? '').trim()}\n`;
}

export function ensureTags(fm) {
  const tags = new Set([...(Array.isArray(fm?.tags) ? fm.tags : []), ...REQUIRED_TAGS]);
  if (fm?.type) tags.add(fm.type);
  return { ...fm, tags: [...tags] };
}

export function validateFrontmatter(fm) {
  const errors = [];
  if (!TYPES.includes(fm?.type)) errors.push('type must be concept|entity|synthesis|ephemeral');
  if (!fm?.title || typeof fm.title !== 'string') errors.push('title required');
  if (!fm?.slug || !SLUG_RE.test(fm.slug)) errors.push('slug must be ASCII kebab-case');
  if (!Array.isArray(fm?.sources)) errors.push('sources must be an array');
  if (!Array.isArray(fm?.related)) errors.push('related must be an array');
  if (!Array.isArray(fm?.tags) || !REQUIRED_TAGS.every((tag) => fm.tags.includes(tag))) {
    errors.push('tags must include ai-generated, llm-wiki');
  }
  if (fm?.aliases != null && !Array.isArray(fm.aliases)) errors.push('aliases must be an array');
  if (fm?.confidence != null && !['high', 'medium', 'low'].includes(fm.confidence)) errors.push('confidence must be high|medium|low');
  if (!fm?.created) errors.push('created required');
  if (!fm?.updated) errors.push('updated required');
  return { ok: errors.length === 0, errors };
}
