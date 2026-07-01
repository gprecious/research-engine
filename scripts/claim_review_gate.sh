#!/usr/bin/env bash
set -euo pipefail
# Usage: claim_review_gate.sh <source_count> <lens_generated:true|false> [--review|--no-review]
# Prints: {"gate":"on|off","reason":"..."}
SRC=${1:?"usage: claim_review_gate.sh <source_count> <lens_generated> [--review|--no-review]"}
LENS=${2:?"usage: claim_review_gate.sh <source_count> <lens_generated> [--review|--no-review]"}
FLAG=${3:-}

case "$FLAG" in
  --no-review) printf '{"gate":"off","reason":"disabled-flag"}\n'; exit 0 ;;
  --review)    printf '{"gate":"on","reason":"forced"}\n';         exit 0 ;;
esac

if [ "$SRC" -lt 2 ]; then
  printf '{"gate":"off","reason":"too-few-sources"}\n'; exit 0
fi
if [ "$LENS" = "true" ]; then
  printf '{"gate":"on","reason":"lens-planned"}\n'; exit 0
fi
if [ "$SRC" -ge 4 ]; then
  printf '{"gate":"on","reason":"multi-source"}\n'; exit 0
fi
printf '{"gate":"off","reason":"narrow-single-lens"}\n'
