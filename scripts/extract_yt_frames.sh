#!/usr/bin/env bash
# Extract one still frame per chapter (or per arbitrary timestamp) from a
# cached YouTube video. Used by /research-visualize --images under
# strategy A (youtube input_type).
#
# Usage:
#   extract_yt_frames.sh <video_id> <cache_dir> <figures_dir> <spec_json>
#
# <spec_json> is a JSON file with the shape:
#   {
#     "items": [
#       { "n": 1, "title": "Affordances & Signifiers", "t_sec": 18.0 },
#       ...
#     ]
#   }
#
# The script:
#   1. Ensures cache_dir/<video_id>.mp4 exists (downloads via yt-dlp if not).
#   2. For each item, runs ffmpeg to extract 1 frame at t_sec into
#      figures_dir/frame-NN-<slug(title)>.jpg (JPEG quality 3).
#   3. Prints a JSON report to stdout:
#        { "rendered": [ {n, title, t_sec, png_rel, ok, size} ], "failures": [...] }
#
# No deletion. Idempotent: existing frame files are overwritten.
set -euo pipefail

VIDEO_ID="${1:-}"
CACHE_DIR="${2:-}"
FIG_DIR="${3:-}"
SPEC="${4:-}"

if [[ -z "$VIDEO_ID" || -z "$CACHE_DIR" || -z "$FIG_DIR" || -z "$SPEC" ]]; then
  echo "usage: extract_yt_frames.sh <video_id> <cache_dir> <figures_dir> <spec_json>" >&2
  exit 2
fi
command -v yt-dlp >/dev/null || { echo "extract_yt_frames: yt-dlp not installed" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "extract_yt_frames: ffmpeg not installed" >&2; exit 1; }
command -v jq     >/dev/null || { echo "extract_yt_frames: jq not installed"     >&2; exit 1; }
[[ -f "$SPEC" ]] || { echo "extract_yt_frames: spec not found: $SPEC" >&2; exit 2; }

mkdir -p "$CACHE_DIR" "$FIG_DIR"
VIDEO_FILE="$CACHE_DIR/${VIDEO_ID}.mp4"

# Download low-res mp4 if not cached.
if [[ ! -f "$VIDEO_FILE" ]]; then
  echo "extract_yt_frames: downloading ${VIDEO_ID} (≤480p mp4)" >&2
  yt-dlp -f "bv*[height<=480][ext=mp4]+ba/b[height<=480]" --merge-output-format mp4 \
    -o "$CACHE_DIR/${VIDEO_ID}.%(ext)s" \
    "https://www.youtube.com/watch?v=${VIDEO_ID}" >&2
fi
[[ -f "$VIDEO_FILE" ]] || { echo "extract_yt_frames: download failed: $VIDEO_FILE" >&2; exit 1; }

# Process each spec item. Collect results into JSON arrays via jq.
RENDERED='[]'
FAILURES='[]'

# Stream spec items line-by-line: {"n":...,"title":"...","t_sec":...}
while IFS= read -r item; do
  [[ -z "$item" ]] && continue
  n="$(jq -r '.n' <<< "$item")"
  title="$(jq -r '.title' <<< "$item")"
  t_sec="$(jq -r '.t_sec' <<< "$item")"
  # zero-pad n to 2 digits
  printf -v nn '%02d' "$n"
  # slugify via scripts/slugify.sh in same dir
  dir="$(dirname "$0")"
  slug="$("$dir/slugify.sh" "$title")"
  out="$FIG_DIR/frame-${nn}-${slug}.jpg"
  # -nostdin: ffmpeg otherwise eats characters from the enclosing while-read
  # loop's stdin (process-substitution fd), corrupting the next spec line.
  if ffmpeg -nostdin -y -ss "$t_sec" -i "$VIDEO_FILE" -frames:v 1 -q:v 3 "$out" >/dev/null 2>&1 \
     && [[ -s "$out" ]]; then
    size="$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out" 2>/dev/null || echo 0)"
    RENDERED="$(jq --argjson a "$RENDERED" \
      --arg n "$n" --arg title "$title" --arg t "$t_sec" \
      --arg png_rel "figures/$(basename "$out")" --arg size "$size" -n '
      $a + [{n: ($n|tonumber), title: $title, t_sec: ($t|tonumber),
             png_rel: $png_rel, ok: true, size: ($size|tonumber)}]')"
  else
    FAILURES="$(jq --argjson a "$FAILURES" \
      --arg n "$n" --arg title "$title" --arg t "$t_sec" -n '
      $a + [{n: ($n|tonumber), title: $title, t_sec: ($t|tonumber),
             error: "ffmpeg_failed"}]')"
  fi
done < <(jq -c '.items[]' "$SPEC")

jq -n --argjson r "$RENDERED" --argjson f "$FAILURES" '{rendered: $r, failures: $f}'
