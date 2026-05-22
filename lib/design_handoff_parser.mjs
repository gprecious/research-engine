import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

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
  throw new Error('not implemented');
}
