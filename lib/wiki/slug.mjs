import { createHash } from 'node:crypto';

export function slugify(title) {
  if (title == null || !String(title).trim()) return '';
  const ascii = String(title)
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '') // 라틴 발음기호 제거
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (ascii) return ascii;
  // 비ASCII 제목(예: 한글 only): ASCII 보장을 위해 결정적 해시 suffix
  const h = createHash('sha1').update(String(title)).digest('hex').slice(0, 6);
  return `n-${h}`;
}
