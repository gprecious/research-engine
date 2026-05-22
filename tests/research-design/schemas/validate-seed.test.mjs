import { test, expect } from 'vitest';
import Ajv from 'ajv';
import addFormats from 'ajv-formats';
import { readFileSync } from 'node:fs';

const schema = JSON.parse(readFileSync('tests/research-design/schemas/scenarios.schema.json', 'utf8'));
const seed = JSON.parse(readFileSync('research/2026-05-22-ai-image-vectorization-service/design/scenarios.json', 'utf8'));

const ajv = new Ajv({ strict: false });
addFormats(ajv);
// AJV 8.x requires explicit draft-2020-12 meta-schema import
const { default: draft2020 } = await import('ajv/dist/2020.js').catch(() => ({ default: null }));
const ajv2020 = draft2020 ? new draft2020({ strict: false }) : ajv;
if (draft2020) addFormats(ajv2020);
const compiler = draft2020 ? ajv2020 : ajv;
const validate = compiler.compile(schema);

test('시드 scenarios.json 이 schema 통과', () => {
  const ok = validate(seed);
  expect(ok, JSON.stringify(validate.errors)).toBe(true);
});

test('시드 슬러그가 디렉토리 슬러그와 일치', () => {
  expect(seed.slug).toBe('2026-05-22-ai-image-vectorization-service');
});
