#!/usr/bin/env node
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { extractRegions } from './extract_evolvable.mjs';

const [, , agentPath, regionId] = process.argv;
const src = readFileSync(agentPath, 'utf8');
const region = extractRegions(src).find((r) => r.id === regionId);
if (!region) {
  console.error(`region ${regionId} not found in ${agentPath}`);
  process.exit(2);
}

const __dirname = dirname(fileURLToPath(import.meta.url));
const dreamsDir = resolve(__dirname, '../../docs/dreams');
const dreamExcerpts = [];
if (existsSync(dreamsDir)) {
  const dirs = readdirSync(dreamsDir).filter((d) => d.startsWith('drm_')).sort().slice(-3);
  for (const d of dirs) {
    const readme = `${dreamsDir}/${d}/README.md`;
    if (existsSync(readme)) {
      dreamExcerpts.push({ run_id: d, text: readFileSync(readme, 'utf8').slice(0, 4000) });
    }
  }
}

console.log(JSON.stringify({
  adapter_name: agentPath.split('/').pop().replace('.md', ''),
  region_id: regionId,
  current_body: region.body,
  dream_excerpts: dreamExcerpts,
  bench_weaknesses: [],
  n_variants: 2,
}, null, 2));
