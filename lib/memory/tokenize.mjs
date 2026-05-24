export function tokenize(input) {
  if (input == null) return [];
  const text = String(input).normalize('NFC');
  const matches = [];
  for (const m of text.matchAll(/[가-힣]+|[a-zA-Z]+/g)) {
    matches.push({ token: m[0], offset: m.index, isHangul: /[가-힣]/.test(m[0]) });
  }
  return matches
    .filter(m => m.isHangul || m.token.length >= 2)
    .map(m => m.isHangul ? m.token : m.token.toLowerCase());
}
