import { describe, it, expect } from 'vitest';
import { tokenize } from './tokenize.mjs';

describe('tokenize', () => {
  it('영문 단어를 소문자로 분리한다', () => {
    expect(tokenize('Memory and Dreaming for Self-Learning Agents')).toEqual(
      ['memory', 'and', 'dreaming', 'for', 'self', 'learning', 'agents']
    );
  });

  it('한글 어절을 그대로 분리한다', () => {
    expect(tokenize('에이전트 메모리 시스템')).toEqual(
      ['에이전트', '메모리', '시스템']
    );
  });

  it('한·영 혼합 입력을 모두 처리한다', () => {
    expect(tokenize('Anthropic Memory & 드리밍 설계')).toEqual(
      ['anthropic', 'memory', '드리밍', '설계']
    );
  });

  it('영문 길이 2 미만 토큰을 제외하고, 한글은 보존한다', () => {
    expect(tokenize('AI a b 한 글')).toEqual(['ai', '한', '글']);
  });

  it('NFC 정규화로 같은 결과를 만든다', () => {
    const composed = '한글';
    const decomposed = '한글'.normalize('NFD');
    expect(tokenize(composed)).toEqual(tokenize(decomposed));
  });

  it('null/undefined/빈 문자열에 빈 배열을 반환한다', () => {
    expect(tokenize(null)).toEqual([]);
    expect(tokenize(undefined)).toEqual([]);
    expect(tokenize('')).toEqual([]);
  });
});
