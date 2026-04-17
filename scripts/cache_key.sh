#!/usr/bin/env bash
# SHA-1 of the input, first 12 hex chars. Stable cache key for a URL.
# Usage: cache_key.sh <url>
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: cache_key.sh <url>" >&2
  exit 2
fi

printf '%s' "$1" | shasum -a 1 | cut -c1-12
