import { mkdirSync, copyFileSync } from 'node:fs';
import { join, dirname } from 'node:path';

export function nextVersion(history) {
  if (!history || history.length === 0) return 1;
  return Math.max(...history.map((h) => h.version)) + 1;
}

export function archivePath(agentsDir, name, version) {
  return `${agentsDir}/archive/${name}.v${version}.md`;
}

export function archiveCurrent({ agentsDir, name, version }) {
  const src = join(agentsDir, `${name}.md`);
  const dst = archivePath(agentsDir, name, version);
  mkdirSync(dirname(dst), { recursive: true });
  copyFileSync(src, dst);
  return dst;
}
