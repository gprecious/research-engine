import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { topK } from './similarity.mjs';
import { tokenize } from './tokenize.mjs';

const args = process.argv.slice(2);
const get = (flag) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : null;
};

const manifestPath = get('--manifest');
const targetJson = get('--target-json');
const selfSlug = get('--self-slug') ?? null;
const k = parseInt(get('--top-k') ?? '5', 10);

const empty = { similar_sessions: [], dream_insights: [] };

try {
  if (!manifestPath || !targetJson) {
    process.stdout.write(JSON.stringify(empty) + '\n');
    process.exit(0);
  }
  const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8'));
  const target = JSON.parse(targetJson);
  target.slug = selfSlug;
  target.intent = target.intent ?? {};
  const purposeText = (target.intent.purpose ?? '') + ' ' + (target.intent.focus ?? '');
  target.intent.purpose_tokens = tokenize(purposeText);

  const targetPurposeTokens = new Set(target.intent?.purpose_tokens ?? []);
  const targetTopics = new Set(target.topics ?? []);

  const similar = topK(target, manifest.sessions ?? [], k)
    .filter(s => {
      // type 일치만으로는 포함하지 않음 — purpose_tokens 또는 topics 교차가 1개 이상 필요
      const purposeOverlap = (s.intent?.purpose_tokens ?? []).some(t => targetPurposeTokens.has(t));
      const topicOverlap = (s.topics ?? []).some(t => targetTopics.has(t));
      return purposeOverlap || topicOverlap;
    })
    .map(s => ({
      slug: s.slug,
      title: s.title,
      input_type: s.input_type,
      input: s.input,
      topics: s.topics,
      notion_url: s.notion_url,
      path: s.path,
      score: s._score
    }));

  const active_dreams = (manifest.dreams ?? [])
    .filter(d => d.status === 'active')
    .map(d => ({ run_id: d.run_id, path: d.path, insight_files: d.insight_files, inputs: d.inputs }));

  process.stdout.write(JSON.stringify({ similar_sessions: similar, dream_insights: active_dreams }) + '\n');
} catch (err) {
  process.stderr.write(`query_cli: ${err.message}\n`);
  process.stdout.write(JSON.stringify(empty) + '\n');
  process.exit(0);
}
