export function dominates(a, b, axes) {
  const keys = axes || Object.keys(a).filter((k) => typeof a[k] === 'number');
  let anyStrict = false;
  for (const k of keys) {
    if (a[k] < b[k]) return false;
    if (a[k] > b[k]) anyStrict = true;
  }
  return anyStrict;
}

export function paretoFront(points, axes) {
  return points.filter((p) =>
    !points.some((q) => q !== p && dominates(q, p, axes))
  );
}
