#!/usr/bin/env bash
# collect_metrics.sh — extract per-run quantitative metrics
# Usage: collect_metrics.sh <run_dir> <start_unix> <end_unix>
# Writes <run_dir>/meta.json. Always exits 0.
#
# Reads:
#   <run_dir>/output.md   — markdown research content (word/citation/link counts)
#   <run_dir>/raw.json    — claude -p --output-format=json envelope (token counts)
#
# Spike (Task 2) showed claude exposes tokens via JSON stdout, not stderr lines.
# Token format: .usage.input_tokens / .usage.output_tokens

set -euo pipefail

RUN_DIR="${1:?run_dir required}"
START="${2:?start required}"
END="${3:?end required}"

OUTPUT="$RUN_DIR/output.md"
RAW="$RUN_DIR/raw.json"
META="$RUN_DIR/meta.json"

WALL=$(( END - START ))

if [[ ! -s "$OUTPUT" ]]; then
  jq -n --argjson wall "$WALL" \
    '{status:"failed", wall_time_sec:$wall, word_count:0, citation_count:0, external_link_count:0, model_tokens:null, exit_code:null}' \
    > "$META"
  exit 0
fi

WORDS=$(wc -w < "$OUTPUT" | tr -d ' ')

# Numbered citations [1], [2], etc — count occurrences (not unique).
CITATIONS=$(grep -oE '\[[0-9]+\]' "$OUTPUT" | wc -l | tr -d ' ')

# External links: any URL appearing as bare http(s):// or in markdown link form.
LINKS=$(grep -oE 'https?://[^ )"]+' "$OUTPUT" | sort -u | wc -l | tr -d ' ')

# Token usage from raw.json (claude -p --output-format=json envelope).
TOKENS_JSON="null"
if [[ -f "$RAW" ]]; then
  if INPUT=$(jq -r '.usage.input_tokens // empty' "$RAW" 2>/dev/null) && \
     OUTPUT_T=$(jq -r '.usage.output_tokens // empty' "$RAW" 2>/dev/null) && \
     [[ -n "$INPUT" && -n "$OUTPUT_T" ]]; then
    TOKENS_JSON=$(jq -n --argjson i "$INPUT" --argjson o "$OUTPUT_T" '{input:$i, output:$o}')
  fi
fi

jq -n \
  --argjson wall "$WALL" \
  --argjson words "$WORDS" \
  --argjson cit "$CITATIONS" \
  --argjson links "$LINKS" \
  --argjson tokens "$TOKENS_JSON" \
  '{status:"ok", wall_time_sec:$wall, word_count:$words, citation_count:$cit, external_link_count:$links, model_tokens:$tokens, exit_code:0}' \
  > "$META"
