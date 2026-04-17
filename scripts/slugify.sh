#!/usr/bin/env bash
# Lowercase, hyphenate whitespace, drop punctuation, cap at 40 chars.
# Preserves Unicode letters (Hangul, CJK, Hiragana, Katakana) so non-ASCII
# titles remain readable.
# Usage: slugify.sh <text>
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: slugify.sh <text>" >&2
  exit 2
fi

printf '%s' "$1" | perl -CSDA -Mutf8 -pe '
  $_ = lc $_;
  s/[^\p{L}\p{N}\s_-]//g;
  s/[\s_]+/-/g;
  s/-+/-/g;
  s/^-+|-+$//g;
  $_ = substr($_, 0, 40);
  s/-+$//;
'
