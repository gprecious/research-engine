#!/usr/bin/env node
import { readFileSync, copyFileSync, unlinkSync, existsSync } from 'node:fs';
import { archiveCurrent } from './archive.mjs';

const [, , ledgerPath, agentsDir, name] = process.argv;
const ledger = JSON.parse(readFileSync(ledgerPath, 'utf8'));
const cur = ledger.adapters[name];
if (!cur) { console.error('no adapter in ledger'); process.exit(2); }

const candPath = `${agentsDir}/${name}.candidate.md`;
if (!existsSync(candPath)) { console.error('no candidate file'); process.exit(2); }

// history holds promoted entries chronologically. The last is the just-promoted (current_version).
// The previous promoted version is the second-to-last, if any.
const prevPromoted = cur.history.slice(-2, -1)[0];
if (prevPromoted) archiveCurrent({ agentsDir, name, version: prevPromoted.version });

copyFileSync(candPath, `${agentsDir}/${name}.md`);
unlinkSync(candPath);

console.log(JSON.stringify({ promoted: name, new_version: cur.current_version }, null, 2));
