import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { validateScenarios } from './scenarios_validator.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const fix = (name) => JSON.parse(readFileSync(resolve(__dirname, `../tests/research-engine/fixtures/${name}`), 'utf8'));

describe('scenarios_validator', () => {
  it('accepts valid scenarios', () => {
    const result = validateScenarios(fix('scenarios-valid.json'));
    expect(result.valid).toBe(true);
    expect(result.errors).toEqual([]);
  });

  it('rejects scenarios missing required fields', () => {
    const result = validateScenarios(fix('scenarios-missing-field.json'));
    expect(result.valid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors.some(e => /baseUrl/.test(e.instancePath + e.message))).toBe(true);
  });

  it('accepts scenarios with optional _meta field', () => {
    const result = validateScenarios(fix('scenarios-with-meta.json'));
    expect(result.valid).toBe(true);
  });
});
