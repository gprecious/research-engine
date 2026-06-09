#!/usr/bin/env bash
set -euo pipefail

BUDGET="${WIKI_LIBRARIAN_BUDGET:-50}"
PROMPT="/wiki librarian --apply --budget ${BUDGET}"
CMD=(claude -p "${PROMPT}")

if [ "${1:-}" = "--dry-run" ]; then
  printf 'claude -p "%s"\n' "${PROMPT}"
  exit 0
fi

exec "${CMD[@]}"
