import Ajv from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const schemaPath = resolve(__dirname, '../tests/research-engine/schemas/claim_review.schema.json');
const schema = JSON.parse(readFileSync(schemaPath, 'utf8'));

const ajv = new Ajv({ allErrors: true, strict: false });
addFormats(ajv);
const validate = ajv.compile(schema);

export function validateClaimReview(obj) {
  const valid = validate(obj);
  const errs = validate.errors || [];
  return { valid, errors: errs.map(e => ({ instancePath: e.instancePath, message: e.message, keyword: e.keyword, params: e.params })) };
}

export function validateClaimReviewFile(path) {
  return validateClaimReview(JSON.parse(readFileSync(path, 'utf8')));
}

// CLI: node lib/claim_review_validator.mjs <file>  -> exit 0 + "OK", or exit 1 + errors JSON
if (process.argv[1] && process.argv[1].endsWith('claim_review_validator.mjs')) {
  const res = validateClaimReviewFile(process.argv[2]);
  if (res.valid) { console.log('OK'); process.exit(0); }
  console.error(JSON.stringify(res.errors, null, 2));
  process.exit(1);
}
