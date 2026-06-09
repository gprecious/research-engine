export function appendChangeLog(text, { date, kind, detail }) {
  const line = `- [${date}] ${kind} | ${detail}`;
  const base = String(text ?? '').trimEnd();
  return `${base ? `${base}\n` : ''}${line}\n`;
}
