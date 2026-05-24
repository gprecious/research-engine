#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs';
import { pairedBootstrapCI, gateDecision } from './statistical_gate.mjs';
import { initLedger, promote, reject } from './ledger.mjs';

const [, , ledgerPath, name, curJsonPath, candJsonPath] = process.argv;
const cur = JSON.parse(readFileSync(curJsonPath, 'utf8'));   // {scores: [..]}
const cand = JSON.parse(readFileSync(candJsonPath, 'utf8'));

const ci = pairedBootstrapCI(cur.scores, cand.scores, { iters: 2000, seed: 42 });
const dec = gateDecision(ci);

let ledger;
try { ledger = JSON.parse(readFileSync(ledgerPath, 'utf8')); }
catch { ledger = initLedger(); }

function nextVersionFor(adapter) {
  if (!adapter) return 1;
  const all = [
    ...(adapter.history || []),
    ...(adapter.frontier || []),
    ...(adapter.rejected || []),
  ];
  const maxV = all.reduce((m, e) => Math.max(m, e.version || 0), 0);
  return maxV + 1;
}

const nextVer = nextVersionFor(ledger.adapters[name]);
const metrics = {
  judge_score: cand.scores.reduce((a, b) => a + b, 0) / cand.scores.length,
  source_count: cand.source_count ?? 0,
  type_diversity: cand.type_diversity ?? 0,
  latency_inv: cand.latency_inv ?? 0,
};

const now = new Date().toISOString();
const entry = {
  version: nextVer,
  ci_lower: ci.lower,
  metrics,
};
if (dec === 'accept') {
  entry.promoted_at = now;
  ledger = promote(ledger, name, entry);
} else if (dec === 'reject') {
  entry.rejected_at = now;
  ledger = reject(ledger, name, entry);
} else { // hold
  entry.held_at = now;
  // intentionally do not mutate ledger; just report the entry
}

writeFileSync(ledgerPath, JSON.stringify(ledger, null, 2));
console.log(JSON.stringify({ decision: dec, ci, entry }, null, 2));
