import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { validateClaimReview } from './claim_review_validator.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const fix = (name) => JSON.parse(readFileSync(resolve(__dirname, `../tests/research-engine/fixtures/${name}`), 'utf8'));

describe('claim_review_validator', () => {
  it('accepts a reviewed claim set', () => {
    const r = validateClaimReview(fix('claim_review-valid.json'));
    expect(r.valid).toBe(true);
    expect(r.errors).toEqual([]);
  });
  it('accepts a no-op (reviewed:false) sentinel', () => {
    expect(validateClaimReview(fix('claim_review-noop.json')).valid).toBe(true);
  });
  it('rejects a claim missing confidence', () => {
    const r = validateClaimReview(fix('claim_review-missing-field.json'));
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => /confidence/.test(e.instancePath + e.message))).toBe(true);
  });
});
