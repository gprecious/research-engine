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

function recomputeFrontier(prevFrontier, entry) {
  const candidates = [...prevFrontier, entry];
  const newFront = paretoFront(
    candidates.map((c) => ({ ...c.metrics, _ref: c })),
    AXES
  ).map((p) => p._ref);
  const shedOut = prevFrontier.filter((p) => !newFront.includes(p));
  return { newFront, shedOut, entryOnFront: newFront.includes(entry) };
}

export function promote(l, name, entry) {
  const a = ensureAdapter(l, name);
  a.current_version = entry.version;
  a.promoted_at = entry.promoted_at;
  a.history.push(entry);
  const { newFront, shedOut } = recomputeFrontier(a.frontier, entry);
  a.frontier = newFront;
  a.rejected.push(...shedOut);
  return l;
}

export function reject(l, name, entry) {
  const a = ensureAdapter(l, name);
  const { newFront, shedOut, entryOnFront } = recomputeFrontier(a.frontier, entry);
  if (entryOnFront) {
    a.frontier = newFront;
    a.rejected.push(...shedOut);
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
