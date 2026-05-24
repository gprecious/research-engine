const W_TYPE = 3;
const W_TOPIC = 2;
const W_PURPOSE = 1;

function intersectionCount(a, b) {
  const setB = new Set(b);
  let count = 0;
  for (const x of a) if (setB.has(x)) count++;
  return count;
}

export function scoreSession(target, candidate) {
  let score = 0;
  if (target.input_type && candidate.input_type === target.input_type) score += W_TYPE;
  score += intersectionCount(target.topics ?? [], candidate.topics ?? []) * W_TOPIC;
  score += intersectionCount(
    target.intent?.purpose_tokens ?? [],
    candidate.intent?.purpose_tokens ?? []
  ) * W_PURPOSE;
  return score;
}

export function topK(target, candidates, k) {
  const scored = candidates
    .filter(c => target.slug == null || c.slug !== target.slug)
    .map(c => ({ ...c, _score: scoreSession(target, c) }))
    .filter(c => c._score > 0);
  scored.sort((a, b) => {
    if (b._score !== a._score) return b._score - a._score;
    return String(b.created ?? '').localeCompare(String(a.created ?? ''));
  });
  return scored.slice(0, k);
}
