#!/usr/bin/env node
/**
 * Usage:
 *   node scripts/judge_app.mjs \
 *     --app-screenshot path/to/app.png \
 *     --design-screenshot path/to/design.png \
 *     --scenarios path/to/scenarios.json \
 *     --out path/to/score.json
 *
 * Optionally `--mock` returns a fixed score for tests.
 */
import { writeFileSync } from 'node:fs';

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i++) {
    const k = argv[i];
    if (k.startsWith('--')) {
      const key = k.slice(2);
      const v = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
      out[key] = v;
    }
  }
  return out;
}

export async function judge({ appScreenshot, designScreenshot, scenariosPath, mock = false }) {
  if (mock) {
    return {
      designQuality: 78,
      originality: 72,
      craft: 80,
      functionality: 76,
      total: 76.5,
      axisNotes: {
        designQuality: 'mock',
        originality: 'mock',
        craft: 'mock',
        functionality: 'mock'
      }
    };
  }
  throw new Error('not implemented');
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = parseArgs(process.argv);
  const result = await judge({
    appScreenshot: args['app-screenshot'],
    designScreenshot: args['design-screenshot'],
    scenariosPath: args.scenarios,
    mock: !!args.mock
  });
  if (args.out) writeFileSync(args.out, JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
}
