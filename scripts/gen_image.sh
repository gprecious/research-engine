#!/usr/bin/env bash
# Image generation backend dispatcher for /research-visualize --images (strategy B).
#
# Usage:
#   gen_image.sh --prompt "…" --out /abs/path/out.png [--aspect 16:9]
#
# Chooses a backend in priority order based on environment:
#   1. IMAGEGEN_REPLICATE_TOKEN + IMAGEGEN_REPLICATE_MODEL  → Replicate REST API
#   2. IMAGEGEN_CLAUDE_CMD                                  → shells out to user-supplied
#                                                             command (for bespoke setups;
#                                                             must write <out> itself)
#
# Anthropic/Claude does NOT have a first-party image-gen API at present, so
# "claude-cli" mode is modelled as a pluggable user command — set
# IMAGEGEN_CLAUDE_CMD to something like:
#   'claude --image "$PROMPT" --output "$OUT"'
# and this script will invoke it with PROMPT / OUT / ASPECT in env.
#
# If no backend is configured, exits non-zero with a clear error — the caller
# is expected to fall back to another strategy.

set -euo pipefail

PROMPT=""
OUT=""
ASPECT="16:9"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) PROMPT="$2"; shift 2 ;;
    --out)    OUT="$2"; shift 2 ;;
    --aspect) ASPECT="$2"; shift 2 ;;
    *) echo "gen_image: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$PROMPT" ]] || { echo "gen_image: --prompt required" >&2; exit 2; }
[[ -n "$OUT"    ]] || { echo "gen_image: --out required"    >&2; exit 2; }

mkdir -p "$(dirname "$OUT")"

# --- Backend 1: Replicate (external API) ---
if [[ -n "${IMAGEGEN_REPLICATE_TOKEN:-}" && -n "${IMAGEGEN_REPLICATE_MODEL:-}" ]]; then
  echo "gen_image: using Replicate backend ($IMAGEGEN_REPLICATE_MODEL)" >&2
  body="$(jq -n --arg p "$PROMPT" --arg ar "$ASPECT" '{
    input: { prompt: $p, aspect_ratio: $ar }
  }')"
  create="$(curl -sS -X POST "https://api.replicate.com/v1/models/${IMAGEGEN_REPLICATE_MODEL}/predictions" \
    -H "Authorization: Bearer ${IMAGEGEN_REPLICATE_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "$body")"
  pred_id="$(jq -r '.id // empty' <<< "$create")"
  if [[ -z "$pred_id" ]]; then
    echo "gen_image: replicate create failed: $create" >&2
    exit 1
  fi
  # Poll until succeeded / failed
  for _ in $(seq 1 60); do
    sleep 2
    status_resp="$(curl -sS "https://api.replicate.com/v1/predictions/${pred_id}" \
      -H "Authorization: Bearer ${IMAGEGEN_REPLICATE_TOKEN}")"
    status="$(jq -r '.status' <<< "$status_resp")"
    case "$status" in
      succeeded) break ;;
      failed|canceled)
        echo "gen_image: replicate prediction $status: $status_resp" >&2; exit 1 ;;
    esac
  done
  url="$(jq -r '.output | if type=="array" then .[0] else . end // empty' <<< "$status_resp")"
  [[ -n "$url" ]] || { echo "gen_image: no output url from replicate: $status_resp" >&2; exit 1; }
  curl -sSL "$url" -o "$OUT"
  [[ -s "$OUT" ]] || { echo "gen_image: download failed" >&2; exit 1; }
  exit 0
fi

# --- Backend 2: User-supplied claude / wrapper command ---
if [[ -n "${IMAGEGEN_CLAUDE_CMD:-}" ]]; then
  echo "gen_image: using user-supplied IMAGEGEN_CLAUDE_CMD" >&2
  PROMPT="$PROMPT" OUT="$OUT" ASPECT="$ASPECT" bash -c "$IMAGEGEN_CLAUDE_CMD"
  [[ -s "$OUT" ]] || { echo "gen_image: claude cmd did not write $OUT" >&2; exit 1; }
  exit 0
fi

echo "gen_image: no image-gen backend configured." >&2
echo "  Set one of:" >&2
echo "    IMAGEGEN_REPLICATE_TOKEN + IMAGEGEN_REPLICATE_MODEL (e.g. black-forest-labs/flux-schnell)" >&2
echo "    IMAGEGEN_CLAUDE_CMD (shell fragment that reads \$PROMPT / \$OUT / \$ASPECT)" >&2
exit 3
