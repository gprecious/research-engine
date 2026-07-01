#!/usr/bin/env bash
set -euo pipefail
# Usage: lens_gate.sh <input_type> <preview_status:ok|weak|failed> [--lens|--no-lens]
# Prints: {"gate":"on|off","reason":"..."}  (reason ∈ lens_plan.schema gate_reason enum)
INPUT_TYPE=${1:?"usage: lens_gate.sh <input_type> <preview_status> [--lens|--no-lens]"}
PREVIEW=${2:?"usage: lens_gate.sh <input_type> <preview_status> [--lens|--no-lens]"}
FLAG=${3:-}

case "$FLAG" in
  --no-lens) printf '{"gate":"off","reason":"disabled-flag"}\n'; exit 0 ;;
  --lens)    printf '{"gate":"on","reason":"forced"}\n';         exit 0 ;;
esac

if [ "$INPUT_TYPE" = "topic" ]; then
  printf '{"gate":"on","reason":"topic-mode"}\n'; exit 0
fi
if [ "$PREVIEW" = "weak" ] || [ "$PREVIEW" = "failed" ]; then
  printf '{"gate":"on","reason":"weak-preview"}\n'; exit 0
fi
printf '{"gate":"off","reason":"disabled-narrow-input"}\n'
