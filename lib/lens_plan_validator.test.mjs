import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { validateLensPlan } from './lens_plan_validator.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const fix = (name) => JSON.parse(readFileSync(resolve(__dirname, `../tests/research-engine/fixtures/${name}`), 'utf8'));

describe('lens_plan_validator', () => {
  it('accepts a generated plan with >=2 lenses', () => {
    const r = validateLensPlan(fix('lens_plan-valid.json'));
    expect(r.valid).toBe(true);
    expect(r.errors).toEqual([]);
  });
  it('accepts a no-op (generated:false, empty lenses) sentinel', () => {
    const r = validateLensPlan(fix('lens_plan-noop.json'));
    expect(r.valid).toBe(true);
  });
  it('rejects a lens missing a required field', () => {
    const r = validateLensPlan(fix('lens_plan-missing-field.json'));
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => /rationale/.test(e.instancePath + e.message))).toBe(true);
  });
  it('rejects generated:true with fewer than 2 lenses', () => {
    const r = validateLensPlan(fix('lens_plan-bad-count.json'));
    expect(r.valid).toBe(false);
  });
});
