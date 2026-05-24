const OPEN_RE = /<!--\s*evolvable:([a-z0-9-]+)\s*-->/g;
const CLOSE_RE = /<!--\s*\/evolvable\s*-->/g;

export function extractRegions(src) {
  const tokens = [];
  for (const m of src.matchAll(OPEN_RE)) {
    tokens.push({ kind: 'open', id: m[1], idx: m.index, len: m[0].length });
  }
  for (const m of src.matchAll(CLOSE_RE)) {
    tokens.push({ kind: 'close', idx: m.index, len: m[0].length });
  }
  tokens.sort((a, b) => a.idx - b.idx);

  const regions = [];
  let stack = [];
  for (const t of tokens) {
    if (t.kind === 'open') {
      if (stack.length > 0) {
        throw new Error('nested evolvable markers are not allowed');
      }
      stack.push(t);
    } else {
      if (stack.length === 0) {
        throw new Error('unbalanced evolvable markers — close without open');
      }
      const open = stack.pop();
      const bodyStart = open.idx + open.len;
      const bodyEnd = t.idx;
      const body = src.slice(bodyStart, bodyEnd).replace(/^\n|\n$/g, '');
      regions.push({ id: open.id, body });
    }
  }
  if (stack.length > 0) {
    throw new Error('unbalanced evolvable markers — open without close');
  }
  return regions;
}

export function replaceRegion(src, id, newBody) {
  const open = new RegExp(
    `(<!--\\s*evolvable:${id}\\s*-->)[\\s\\S]*?(<!--\\s*/evolvable\\s*-->)`,
    'm'
  );
  if (!open.test(src)) {
    throw new Error(`region id "${id}" not found`);
  }
  return src.replace(open, `$1\n${newBody}\n$2`);
}
