#!/usr/bin/env bash
# Classify the argument as one of:
#   youtube | arxiv | github | huggingface | community | blog | topic
# Usage: classify_url.sh <input>
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: classify_url.sh <url-or-text>" >&2
  exit 2
fi

input="$1"

# Non-URL → topic
if [[ "$input" != http://* && "$input" != https://* ]]; then
  echo "topic"
  exit 0
fi

case "$input" in
  *youtube.com/*|*youtu.be/*)                       echo "youtube" ;;
  *arxiv.org/*)                                     echo "arxiv" ;;
  *github.com/*)                                    echo "github" ;;
  *huggingface.co/*)                                echo "huggingface" ;;
  *news.ycombinator.com/*|*reddit.com/*|*lobste.rs/*) echo "community" ;;
  *)                                                echo "blog" ;;
esac
