import Ajv from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const schemaPath = resolve(__dirname, '../tests/research-engine/schemas/scenarios.schema.json');
const schema = JSON.parse(readFileSync(schemaPath, 'utf8'));

const ajv = new Ajv({ allErrors: true, strict: true });
addFormats(ajv);
const validate = ajv.compile(schema);

export function validateScenarios(obj) {
  const valid = validate(obj);
  const errs = validate.errors || [];
  return {
    valid,
    errors: errs.map(e => ({
      instancePath: e.instancePath,
      message: e.message,
      keyword: e.keyword,
      params: e.params
    }))
  };
}

export function validateScenariosFile(path) {
  const obj = JSON.parse(readFileSync(path, 'utf8'));
  return validateScenarios(obj);
}
