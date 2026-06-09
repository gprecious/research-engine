export function rebuildIndex(pages) {
  const byType = { concept: [], entity: [] };
  for (const p of pages) (byType[p.type] ??= []).push(p);
  const section = (title, list) => {
    if (!list || list.length === 0) return '';
    const lines = [...list].sort((a, b) => a.slug.localeCompare(b.slug))
      .map(p => `- [[${p.slug}]] — ${p.title}`);
    return `## ${title}\n\n${lines.join('\n')}\n`;
  };
  return [
    '# Wiki Index',
    '',
    '> [!info] 🤖 AI-generated — session-journal/research-engine 가 작성. `tag:#ai-generated` 로 필터.',
    '',
    section('Concepts', byType.concept),
    section('Entities', byType.entity),
  ]
    .filter(Boolean).join('\n').trimEnd() + '\n';
}

export function appendLog(logText, { date, action, slug }) {
  const line = `- [${date}] ${action} | ${slug}`;
  const base = String(logText ?? '').trimEnd();
  return (base ? base + '\n' : '') + line + '\n';
}

// 정확 라인매칭: "| <slug>" 뒤 토큰이 정확히 일치할 때만 true (접두 부분문자열 오탐 방지)
export function isIngested(logText, sourceSlug) {
  return String(logText ?? '').split('\n').some(line => {
    const idx = line.indexOf('| ');
    return idx >= 0 && line.slice(idx + 2).trim() === sourceSlug;
  });
}
