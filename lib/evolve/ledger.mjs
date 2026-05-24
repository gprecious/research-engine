import { paretoFront } from './pareto.mjs';

const AXES = ['judge_score', 'source_count', 'type_diversity', 'latency_inv'];

export function initLedger() {
  return { version: 1, adapters: {} };
}

function ensureAdapter(l, name) {
  if (!l.adapters[name]) {
    l.adapters[name] = {
      current_version: 0,
      promoted_at: null,
      history: [],
      frontier: [],
      rejected: [],
    };
  }
  return l.adapters[name];
}

export function promote(l, name, entry) {
  const a = ensureAdapter(l, name);
  a.current_version = entry.version;
  a.promoted_at = entry.promoted_at;
  a.history.push(entry);
  // recompute frontier including new promoted version
  const candidates = [...a.frontier, entry];
  a.frontier = paretoFront(
    candidates.map((c) => ({ ...c.metrics, _ref: c })),
    AXES
  ).map((p) => p._ref);
  return l;
}

export function reject(l, name, entry) {
  const a = ensureAdapter(l, name);
  // try to add to frontier; if dominated, move to rejected
  const candidates = [...a.frontier, entry];
  const newFront = paretoFront(
    candidates.map((c) => ({ ...c.metrics, _ref: c })),
    AXES
  ).map((p) => p._ref);
  const isOnFront = newFront.includes(entry);
  if (isOnFront) {
    a.frontier = newFront;
  } else {
    a.rejected.push(entry);
  }
  return l;
}

export function getCurrent(l, name) {
  const a = l.adapters[name];
  if (!a) return null;
  return a.history.find((h) => h.version === a.current_version);
}
