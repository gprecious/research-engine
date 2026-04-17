#!/usr/bin/env bash
# Wrapper over yt-dlp for the research-engine preview/full pipelines.
#
# Subcommands:
#   metadata <URL>                       — prints JSON with selected caption lang
#   metadata --from-fixture <PATH>       — same, but reads a local JSON dump (for tests)
#   captions <URL> <DIR>                 — downloads captions into DIR as <id>.<lang>.vtt
#
# Output JSON schema for `metadata`:
# {
#   "id": "...", "title": "...", "description": "...", "uploader": "...",
#   "duration": <seconds>, "language": "<orig>",
#   "chapters": [...], "selected_caption_lang": "<code>",
#   "caption_langs_available": ["ko","en", ...]
# }
#
# Caption language priority: video original language → ko → en → first available.
set -euo pipefail

die() { echo "yt_fetch: $*" >&2; exit 2; }

pick_caption_lang() {
  # $1 = raw JSON dump
  jq -r '
    (.language // "") as $orig
    | ((.subtitles // {}) | keys) as $subs
    | ((.automatic_captions // {}) | keys) as $auto
    | ($subs + $auto | unique) as $all
    | if ($all | length) == 0 then ""
      elif ($all | index($orig)) then $orig
      elif ($all | index("ko")) then "ko"
      elif ($all | index("en")) then "en"
      else $all[0]
      end
  '
}

list_caption_langs() {
  jq -c '
    (((.subtitles // {}) | keys) + ((.automatic_captions // {}) | keys)) | unique
  '
}

case "${1:-}" in
  metadata)
    shift
    if [[ "${1:-}" == "--from-fixture" ]]; then
      shift
      [[ -f "${1:-}" ]] || die "fixture not found: ${1:-}"
      raw="$(cat "$1")"
    else
      [[ -n "${1:-}" ]] || die "metadata needs <URL> or --from-fixture <PATH>"
      raw="$(yt-dlp --skip-download --write-auto-sub --write-sub --dump-json "$1")"
    fi
    lang="$(printf '%s' "$raw" | pick_caption_lang)"
    langs="$(printf '%s' "$raw" | list_caption_langs)"
    printf '%s' "$raw" | jq \
      --arg lang "$lang" \
      --argjson langs "$langs" \
      '. + {selected_caption_lang: $lang, caption_langs_available: $langs}'
    ;;

  captions)
    [[ $# -eq 3 ]] || die "captions needs <URL> <DIR>"
    url="$2"; dir="$3"
    mkdir -p "$dir"
    # Download all available subs and auto-captions (orchestrator will pick).
    yt-dlp \
      --skip-download \
      --write-auto-sub \
      --write-sub \
      --sub-format "vtt" \
      --convert-subs "vtt" \
      -o "$dir/%(id)s.%(ext)s" \
      "$url"
    ;;

  ""|-h|--help)
    sed -n '2,10p' "$0"
    exit 1
    ;;

  *)
    die "unknown subcommand: $1"
    ;;
esac
