#!/usr/bin/env bash
# Print slug of the most recently modified session folder under <research_dir>.
# Exit 1 if directory is missing or empty.
# Usage: find_latest_session.sh <research_dir>
set -euo pipefail

root="${1:-}"
[[ -d "$root" ]] || { echo "find_latest_session: no such dir: $root" >&2; exit 1; }

latest="$(find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\n' 2>/dev/null \
  | sort -rn | head -n1 | cut -d' ' -f2-)"

[[ -n "$latest" ]] || { echo "find_latest_session: no sessions under $root" >&2; exit 1; }
echo "$latest"
