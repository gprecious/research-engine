#!/usr/bin/env node
import { readFileSync, copyFileSync, unlinkSync, existsSync } from 'node:fs';
import { archiveCurrent } from './archive.mjs';

const [, , ledgerPath, agentsDir, name] = process.argv;
const ledger = JSON.parse(readFileSync(ledgerPath, 'utf8'));
const cur = ledger.adapters[name];
if (!cur) { console.error('no adapter in ledger'); process.exit(2); }

const candPath = `${agentsDir}/${name}.candidate.md`;
if (!existsSync(candPath)) { console.error('no candidate file'); process.exit(2); }

// archive current under previous version (= current_version - 1 if just promoted)
const prevVer = cur.current_version - 1;
if (prevVer >= 1) archiveCurrent({ agentsDir, name, version: prevVer });

copyFileSync(candPath, `${agentsDir}/${name}.md`);
unlinkSync(candPath);

console.log(JSON.stringify({ promoted: name, new_version: cur.current_version }, null, 2));
