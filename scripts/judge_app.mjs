#!/usr/bin/env node
/**
 * Usage:
 *   node scripts/judge_app.mjs \
 *     --app-screenshot path/to/app.png \
 *     --design-screenshot path/to/design.png \
 *     --scenarios path/to/scenarios.json \
 *     --out path/to/score.json
 *
 * `--mock` 플래그로 결정적 mock 점수 반환.
 */
import { writeFileSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const RUBRIC = `
4-axis design rubric. Score each 0-100 strictly. Output JSON only:
{"designQuality": <int>, "originality": <int>, "craft": <int>, "functionality": <int>, "axisNotes": {...}}

- designQuality: visual hierarchy, color harmony, typography, spacing
- originality: 차별성. 흔한 AI 템플릿 같지 않은가
- craft: 디테일 (interaction polish, alignment, micro-typography)
- functionality: scenarios.json 항목들이 잘 작동하는 디자인인가
`;

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
      axisNotes: { designQuality: 'mock', originality: 'mock', craft: 'mock', functionality: 'mock' }
    };
  }

  const scenarios = readFileSync(scenariosPath, 'utf8');
  const prompt = `${RUBRIC}\n\nApp screenshot path: ${appScreenshot}\nDesign reference path: ${designScreenshot}\nScenarios JSON:\n${scenarios}\n\nOutput JSON only.`;

  const res = spawnSync('claude', ['-p', prompt], { encoding: 'utf8', timeout: 180000 });
  if (res.status !== 0) throw new Error(`claude -p failed: ${res.stderr || res.stdout}`);

  const m = res.stdout.match(/\{[\s\S]*\}/);
  if (!m) throw new Error(`no JSON in claude output: ${res.stdout.slice(0, 200)}`);
  const parsed = JSON.parse(m[0]);

  const total = (parsed.designQuality + parsed.originality + parsed.craft + parsed.functionality) / 4;
  return { ...parsed, total: Math.round(total * 10) / 10 };
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
