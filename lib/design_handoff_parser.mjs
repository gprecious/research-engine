import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, extname } from 'node:path';

/**
 * @param {string} bundleDir
 * @returns {{
 *   meta: object,
 *   pages: { name: string, html: string }[],
 *   styles: { name: string, css: string }[],
 *   assets: { name: string, path: string, bytes: number }[],
 *   components: string[],
 *   designSystem: object
 * }}
 */
export function parseHandoff(bundleDir) {
  const meta = JSON.parse(readFileSync(join(bundleDir, 'handoff.meta.json'), 'utf8'));
  const entries = readdirSync(bundleDir, { withFileTypes: true });

  const pages = [];
  const styles = [];
  const assets = [];

  for (const e of entries) {
    if (!e.isFile()) continue;
    const full = join(bundleDir, e.name);
    if (e.name.endsWith('.html')) {
      pages.push({ name: e.name, html: readFileSync(full, 'utf8') });
    } else if (e.name.endsWith('.css')) {
      styles.push({ name: e.name, css: readFileSync(full, 'utf8') });
    } else if (['.png', '.jpg', '.jpeg', '.svg', '.webp', '.woff', '.woff2'].includes(extname(e.name))) {
      assets.push({ name: e.name, path: full, bytes: statSync(full).size });
    }
  }

  return {
    meta,
    pages,
    styles,
    assets,
    components: meta.components || [],
    designSystem: meta.designSystem || {}
  };
}
