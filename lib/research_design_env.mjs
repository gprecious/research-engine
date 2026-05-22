import { readFileSync, existsSync } from 'node:fs';

export function loadEnv(path = '.env.research-design') {
  if (!existsSync(path)) return {};
  const out = {};
  const lines = readFileSync(path, 'utf8').split(/\r?\n/);
  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq < 0) continue;
    const k = line.slice(0, eq).trim();
    const v = line.slice(eq + 1).trim().replace(/^["']|["']$/g, '');
    out[k] = v;
  }
  return out;
}

export function requireEnv(keys, env = loadEnv()) {
  const missing = keys.filter((k) => !env[k] && !process.env[k]);
  if (missing.length) throw new Error(`missing env: ${missing.join(', ')}`);
  return Object.fromEntries(keys.map((k) => [k, env[k] ?? process.env[k]]));
}
