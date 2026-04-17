#!/usr/bin/env bash
# Symlinks this plugin directory into ~/.claude/plugins/research-engine so
# Claude Code can discover it. Re-run safely; it removes any existing symlink.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude/plugins/research-engine"

mkdir -p "$HOME/.claude/plugins"

if [[ -L "$TARGET" ]]; then
  rm "$TARGET"
elif [[ -e "$TARGET" ]]; then
  echo "ERROR: $TARGET exists and is not a symlink. Remove it first." >&2
  exit 1
fi

ln -s "$PLUGIN_DIR" "$TARGET"
echo "Linked: $TARGET -> $PLUGIN_DIR"
echo "Restart Claude Code or run /plugins reload."
