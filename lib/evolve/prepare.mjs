#!/usr/bin/env node
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { extractRegions } from './extract_evolvable.mjs';

const MAX_CHARS = 4000;

// argv: <agentPath> <regionId> [--dreams-dir <path>]
const args = process.argv.slice(2);
const positional = [];
let dreamsDirOverride = null;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--dreams-dir') {
    dreamsDirOverride = args[++i];
  } else {
    positional.push(args[i]);
  }
}
const [agentPath, regionId] = positional;

const src = readFileSync(agentPath, 'utf8');
const region = extractRegions(src).find((r) => r.id === regionId);
if (!region) {
  console.error(`region ${regionId} not found in ${agentPath}`);
  process.exit(2);
}

const __dirname = dirname(fileURLToPath(import.meta.url));
const dreamsDir = dreamsDirOverride
  ? resolve(dreamsDirOverride)
  : resolve(__dirname, '../../docs/dreams');

const dreamExcerpts = [];
if (existsSync(dreamsDir)) {
  const dirs = readdirSync(dreamsDir).filter((d) => d.startsWith('drm_')).sort().slice(-3);
  for (const d of dirs) {
    const dreamPath = `${dreamsDir}/${d}`;
    const readmePath = `${dreamPath}/README.md`;
    if (!existsSync(readmePath)) continue;

    const insights = [];
    const insightsDir = `${dreamPath}/insights`;
    if (existsSync(insightsDir)) {
      const files = readdirSync(insightsDir)
        .filter((f) => f.startsWith('pattern-') && f.endsWith('.md'))
        .sort();
      for (const f of files) {
        insights.push({
          name: f.replace(/\.md$/, ''),
          body: readFileSync(`${insightsDir}/${f}`, 'utf8').slice(0, MAX_CHARS),
        });
      }
    }

    dreamExcerpts.push({
      run_id: d,
      readme: readFileSync(readmePath, 'utf8').slice(0, MAX_CHARS),
      insights,
    });
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
