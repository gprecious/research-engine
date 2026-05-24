import fs from 'node:fs/promises';

export function emptyLedger() {
  return {
    version: 1,
    last_dream_run_id: null,
    last_dream_at: null,
    sessions_since_last_dream: [],
    suggestion_threshold: 5,
    suggestion_shown_at: null,
    last_shown_count: 0
  };
}

export function bumpAfterResearch(ledger, slug) {
  if (ledger.sessions_since_last_dream.includes(slug)) return { ...ledger };
  return {
    ...ledger,
    sessions_since_last_dream: [...ledger.sessions_since_last_dream, slug]
  };
}

export function shouldSuggest(ledger) {
  const count = ledger.sessions_since_last_dream.length;
  if (count < ledger.suggestion_threshold) return false;
  if (ledger.suggestion_shown_at == null) return true;
  return count >= ledger.last_shown_count + ledger.suggestion_threshold;
}

export function markSuggested(ledger, nowIso) {
  return {
    ...ledger,
    suggestion_shown_at: nowIso,
    last_shown_count: ledger.sessions_since_last_dream.length
  };
}

export function resetAfterDream(ledger, runId, nowIso) {
  return {
    ...ledger,
    last_dream_run_id: runId,
    last_dream_at: nowIso,
    sessions_since_last_dream: [],
    suggestion_shown_at: null,
    last_shown_count: 0
  };
}

export function rebuildFromManifest(manifest) {
  const activeDreams = (manifest.dreams ?? []).filter(d => d.status === 'active');
  activeDreams.sort((a, b) => String(b.created ?? '').localeCompare(String(a.created ?? '')));
  const latestDream = activeDreams[0] ?? null;

  const sessions = manifest.sessions ?? [];
  const sinceCutoff = latestDream?.created ?? '';
  const sinceList = sessions
    .filter(s => !sinceCutoff || String(s.created ?? '').localeCompare(sinceCutoff) > 0)
    .map(s => s.slug);

  return {
    version: 1,
    last_dream_run_id: latestDream?.run_id ?? null,
    last_dream_at: latestDream?.created ?? null,
    sessions_since_last_dream: sinceList,
    suggestion_threshold: 5,
    suggestion_shown_at: null,
    last_shown_count: 0
  };
}

// CLI
if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const get = (flag) => {
    const i = args.indexOf(flag);
    return i >= 0 ? args[i + 1] : null;
  };
  const cmd = args[0];
  const ledgerPath = get('--ledger');
  if (!ledgerPath) {
    console.error('usage: ledger.mjs <cmd> --ledger <path>');
    process.exit(2);
  }

  async function loadLedger() {
    try { return JSON.parse(await fs.readFile(ledgerPath, 'utf8')); }
    catch { return emptyLedger(); }
  }
  async function saveLedger(l) {
    const tmp = `${ledgerPath}.tmp`;
    await fs.writeFile(tmp, JSON.stringify(l, null, 2) + '\n');
    await fs.rename(tmp, ledgerPath);
  }

  if (cmd === '--rebuild') {
    const manifest = JSON.parse(await fs.readFile(get('--manifest'), 'utf8'));
    const existing = await loadLedger();
    const rebuilt = rebuildFromManifest(manifest);
    rebuilt.suggestion_threshold = existing.suggestion_threshold ?? 5;
    await saveLedger(rebuilt);
  } else if (cmd === '--bump') {
    const l = await loadLedger();
    await saveLedger(bumpAfterResearch(l, get('--slug')));
  } else if (cmd === '--reset') {
    const l = await loadLedger();
    await saveLedger(resetAfterDream(l, get('--run-id'), new Date().toISOString()));
  } else if (cmd === '--suggest?') {
    const l = await loadLedger();
    if (shouldSuggest(l)) {
      await saveLedger(markSuggested(l, new Date().toISOString()));
      process.stdout.write(JSON.stringify({ should: true, count: l.sessions_since_last_dream.length }) + '\n');
      process.exit(0);
    }
    process.stdout.write(JSON.stringify({ should: false, count: l.sessions_since_last_dream.length }) + '\n');
    process.exit(1);
  } else {
    console.error('usage: ledger.mjs --rebuild|--bump|--reset|--suggest? ... --ledger <path>');
    process.exit(2);
  }
}
