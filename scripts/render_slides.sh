#!/usr/bin/env bash
# Render a Marp slides.md to .pptx and .pdf. On any failure, leave slides.md
# untouched and exit non-zero — the orchestrator treats this as non-fatal.
#
# Usage: render_slides.sh <slides.md>
set -euo pipefail

slides="${1:-}"
[[ -f "$slides" ]] || { echo "render_slides: slides.md not found: $slides" >&2; exit 1; }

dir="$(dirname "$slides")"

if ! command -v npx >/dev/null 2>&1; then
  echo "render_slides: npx not on PATH — install Node 18+. slides.md kept as-is." >&2
  exit 2
fi

# --allow-local-files is required so Marp can read figures/*.png referenced with
# relative paths. --html is off by default; we request pptx+pdf explicitly.
cd "$dir"
if ! npx --yes @marp-team/marp-cli@latest "$(basename "$slides")" \
       --pptx --pdf --allow-local-files; then
  echo "render_slides: marp-cli failed (network? node version?). slides.md kept." >&2
  exit 3
fi

echo "slides rendered: $dir/slides.pptx + $dir/slides.pdf"
