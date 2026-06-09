#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
CLAUDE_MANIFEST="${REPO_ROOT}/.claude-plugin/plugin.json"
CODEX_MANIFEST="${REPO_ROOT}/.codex-plugin/plugin.json"

@test "plugin manifests use the same plugin name" {
  claude_name="$(jq -r '.name' "$CLAUDE_MANIFEST")"
  codex_name="$(jq -r '.name' "$CODEX_MANIFEST")"

  [ "$claude_name" = "research-engine" ]
  [ "$codex_name" = "$claude_name" ]
}

@test "plugin manifests use the same release version" {
  claude_version="$(jq -r '.version' "$CLAUDE_MANIFEST")"
  codex_version="$(jq -r '.version' "$CODEX_MANIFEST")"

  [ "$codex_version" = "$claude_version" ]
}

@test "plugin manifests keep release descriptions in sync" {
  claude_description="$(jq -r '.description' "$CLAUDE_MANIFEST")"
  codex_description="$(jq -r '.description' "$CODEX_MANIFEST")"

  [ "$codex_description" = "$claude_description" ]
}
