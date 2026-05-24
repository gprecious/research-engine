// Mulberry32 PRNG for deterministic seeded bootstrap
function mulberry32(seed) {
  let t = seed >>> 0;
  return function () {
    t = (t + 0x6d2b79f5) >>> 0;
    let r = t;
    r = Math.imul(r ^ (r >>> 15), r | 1);
    r ^= r + Math.imul(r ^ (r >>> 7), r | 61);
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

export function pairedBootstrapCI(current, candidate, { iters = 2000, seed = 1, alpha = 0.05 } = {}) {
  if (current.length !== candidate.length) {
    throw new Error(`length mismatch: ${current.length} vs ${candidate.length}`);
  }
  const n = current.length;
  if (n < 2) throw new Error('need at least 2 paired samples');

  const deltas = current.map((c, i) => candidate[i] - c);
  const rand = mulberry32(seed);
  const means = new Array(iters);
  for (let b = 0; b < iters; b++) {
    let sum = 0;
    for (let i = 0; i < n; i++) {
      const idx = Math.floor(rand() * n);
      sum += deltas[idx];
    }
    means[b] = sum / n;
  }
  means.sort((a, b) => a - b);
  const loIdx = Math.floor((alpha / 2) * iters);
  const hiIdx = Math.ceil((1 - alpha / 2) * iters) - 1;
  return {
    mean: deltas.reduce((a, b) => a + b, 0) / n,
    lower: means[loIdx],
    upper: means[hiIdx],
    n,
    iters,
  };
}

export function gateDecision(ci) {
  if (ci.lower > 0) return 'accept';
  if (ci.upper < 0) return 'reject';
  return 'hold';
}
