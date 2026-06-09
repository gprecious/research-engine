import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export function obsidianConfigPaths(home = os.homedir(), env = process.env) {
  const paths = [
    path.join(home, 'Library/Application Support/obsidian/obsidian.json'),
    path.join(home, '.config/obsidian/obsidian.json'),
  ];
  if (env.APPDATA) paths.push(path.join(env.APPDATA, 'obsidian/obsidian.json'));
  return paths;
}

function defaultReadConfig(paths) {
  for (const file of paths) {
    try {
      return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch {
      // Try the next platform-specific config path.
    }
  }
  return null;
}

function selectVaultPath(name, data) {
  const vaults = data?.vaults;
  if (!vaults) return null;

  let best = null;
  for (const info of Object.values(vaults)) {
    if (!info || typeof info.path !== 'string') continue;
    if (path.basename(info.path) !== name) continue;

    const rank = [info.open ? 1 : 0, Number(info.ts) || 0];
    if (!best || rank[0] > best.rank[0] || (rank[0] === best.rank[0] && rank[1] > best.rank[1])) {
      best = { path: info.path, rank };
    }
  }
  return best?.path ?? null;
}

export function resolveNamedVault(name, readConfig = defaultReadConfig) {
  return selectVaultPath(name, readConfig(obsidianConfigPaths()));
}

function cleanSubdir(subdir) {
  return String(subdir || 'LLM-Wiki').replace(/^\/+|\/+$/g, '') || 'LLM-Wiki';
}

export function resolveVault({ env = process.env, cwd = process.cwd(), readConfig } = {}) {
  if (env.WIKI_VAULT) {
    return { dir: env.WIKI_VAULT, mode: 'explicit', ok: true };
  }

  const name = env.LLM_OBSIDIAN_VAULT_NAME;
  if (name) {
    const data = readConfig ? readConfig(obsidianConfigPaths(undefined, env)) : defaultReadConfig(obsidianConfigPaths(undefined, env));
    const base = selectVaultPath(name, data);
    if (base) {
      return { dir: path.join(base, cleanSubdir(env.LLM_WIKI_SUBDIR)), mode: 'name', ok: true };
    }
    return { dir: path.join(cwd, 'wiki'), mode: 'default', ok: false };
  }

  return { dir: path.join(cwd, 'wiki'), mode: 'default', ok: true };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = resolveVault();
  if (process.argv.includes('--explain')) {
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } else {
    process.stdout.write(`${result.dir}\n`);
  }
}
