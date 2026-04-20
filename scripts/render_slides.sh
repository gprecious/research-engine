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
# relative paths. marp-cli rejects --pptx and --pdf together, so invoke twice.
cd "$dir"
base="$(basename "$slides")"
pptx_ok=0; pdf_ok=0
if npx --yes @marp-team/marp-cli@latest "$base" --pptx --allow-local-files; then
  pptx_ok=1
else
  echo "render_slides: pptx render failed (network? node version?)." >&2
fi
if npx --yes @marp-team/marp-cli@latest "$base" --pdf --allow-local-files; then
  pdf_ok=1
else
  echo "render_slides: pdf render failed." >&2
fi

if (( pptx_ok == 0 && pdf_ok == 0 )); then
  echo "render_slides: both pptx and pdf failed — slides.md kept." >&2
  exit 3
fi

produced=()
(( pptx_ok )) && produced+=("$dir/slides.pptx")
(( pdf_ok )) && produced+=("$dir/slides.pdf")
echo "slides rendered: ${produced[*]}"
