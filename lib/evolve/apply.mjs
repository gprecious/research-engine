#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { replaceRegion } from './extract_evolvable.mjs';

const [, , agentPath, regionId, mutatorOutPath] = process.argv;
const src = readFileSync(agentPath, 'utf8');
const out = JSON.parse(readFileSync(mutatorOutPath, 'utf8'));
const v0 = out.variants[0];
if (!v0) { console.error('mutator returned no variants'); process.exit(2); }
process.stdout.write(replaceRegion(src, regionId, v0.body));
