#!/usr/bin/env bash
# Validate <slug>'s session dir under <research_dir>.
# Emit JSON { slug, report_dir, readme, sources } on stdout.
# Usage: load_session.sh <slug> <research_dir>
set -euo pipefail

slug="${1:-}"
root="${2:-}"

[[ -n "$slug" ]] || { echo "load_session: slug required" >&2; exit 2; }
[[ -d "$root" ]] || { echo "load_session: no research dir: $root" >&2; exit 1; }

report_dir="$root/$slug"
[[ -d "$report_dir" ]] || { echo "load_session: no session dir: $report_dir" >&2; exit 1; }

readme="$report_dir/README.md"
[[ -f "$readme" ]] || { echo "load_session: missing README.md in $report_dir" >&2; exit 1; }

sources="$report_dir/sources.json"
[[ -f "$sources" ]] || { echo "load_session: missing sources.json in $report_dir" >&2; exit 1; }

jq -n \
  --arg slug "$slug" \
  --arg dir "$report_dir" \
  --rawfile readme "$readme" \
  --slurpfile src "$sources" \
  '{slug: $slug, report_dir: $dir, readme: $readme, sources: $src[0].sources}'
