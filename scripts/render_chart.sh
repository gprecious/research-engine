#!/usr/bin/env bash
# Render a chart-spec JSON via QuickChart.io.
#
# Usage:
#   render_chart.sh [--preset <name>] [--brand-image <url>] <spec.json> <out.png>
#   render_chart.sh [--preset <name>] [--brand-image <url>] --print-url <spec.json>
#
# --preset aligns chart colors with one of the 5 deck presets from
# lib/style_presets.md (dark-neon, editorial-serif, minimal-swiss,
# warm-neutral-teal, bold-geometric). Without --preset, falls back to the
# Okabe-Ito palette on a white background.
#
# --brand-image <url> injects QuickChart's `backgroundImageUrl` plugin so the
# chart is rendered over a watermark/brand background. The URL must be
# publicly reachable by QuickChart.
#
# When the encoded Chart.js config exceeds ~1900 chars, the script switches
# automatically to POST /chart (JSON body) to avoid GET URL length limits.
# Small configs still use GET so meta.json.quickchart_url stays embeddable in
# Notion.
#
# Exit codes: 0 ok · 2 bad args · 3 validation failed · 4 HTTP/curl failed
set -euo pipefail

preset=""
brand_image=""
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --preset)
      preset="${2:-}"; shift 2 ;;
    --brand-image)
      brand_image="${2:-}"; shift 2 ;;
    --print-url)
      print_url_only=1; shift ;;
    *)
      echo "render_chart: unknown flag: $1" >&2; exit 2 ;;
  esac
done
print_url_only="${print_url_only:-0}"

spec="${1:-}"
out="${2:-}"

[[ -f "$spec" ]] || { echo "render_chart: spec not found: $spec" >&2; exit 2; }
if [[ "$print_url_only" -eq 0 ]]; then
  [[ -n "$out" ]] || { echo "render_chart: out path required" >&2; exit 2; }
fi

# Build the Chart.js config and decide GET vs POST. Python prints one line:
#   GET <url>
#   POST <endpoint> <body_tmpfile>
plan=$(python3 - "$spec" "$preset" "$brand_image" <<'PY'
import json, sys, urllib.parse, tempfile, os

spec_path = sys.argv[1]
preset_name = sys.argv[2] or None
brand_url = sys.argv[3] or None
with open(spec_path, "r", encoding="utf-8") as f:
    spec = json.load(f)

errors = []

allowed_kinds = {"bar", "line", "pie", "scatter", "horizontal_bar", "table"}
kind = spec.get("kind")
if kind not in allowed_kinds:
    errors.append(f"kind must be one of {sorted(allowed_kinds)}, got {kind!r}")

ev = spec.get("evidence") or []
if not ev:
    errors.append("evidence[] is empty")

data = spec.get("data") or {}
datasets = data.get("datasets") or []
quotes = " ||| ".join(e.get("quote_verbatim", "") for e in ev)
for ds in datasets:
    for v in ds.get("values", []):
        if isinstance(v, dict):
            nums = [v.get("x"), v.get("y")]
        else:
            nums = [v]
        for n in nums:
            if n is None:
                continue
            s = ("{:g}".format(n)) if isinstance(n, (int, float)) else str(n)
            if s not in quotes:
                if str(n) not in quotes:
                    errors.append(f"value {n!r} not found in any evidence quote_verbatim")

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(3)

for ds in datasets:
    if "values" in ds:
        ds["data"] = ds.pop("values")

PRESETS = {
    "dark-neon": {
        "bg": "#0A0A0F", "text": "#E6E8EF", "grid": "rgba(230,232,239,0.12)",
        "palette": ["#B6FF3C", "#3DA9FF", "#E6E8EF", "#14141C", "#6DFFC1", "#FF5C8A"],
    },
    "editorial-serif": {
        "bg": "#FAF7F2", "text": "#1B1B1E", "grid": "rgba(27,27,30,0.10)",
        "palette": ["#B54E3A", "#2E5E4E", "#1B1B1E", "#D7B87A", "#8C6F4A", "#4E6E8C"],
    },
    "minimal-swiss": {
        "bg": "#FFFFFF", "text": "#0D0D0D", "grid": "rgba(13,13,13,0.08)",
        "palette": ["#E63946", "#0D4F8B", "#0D0D0D", "#6B7280", "#1F8A8B", "#F59E0B"],
    },
    "warm-neutral-teal": {
        "bg": "#F5EFE4", "text": "#2B241E", "grid": "rgba(43,36,30,0.12)",
        "palette": ["#1F8A8B", "#6B4F3B", "#2B241E", "#C98A5C", "#8C6F4A", "#4E6E8C"],
    },
    "bold-geometric": {
        "bg": "#0E1116", "text": "#F4F4F4", "grid": "rgba(244,244,244,0.12)",
        "palette": ["#FFCC00", "#FF4F4F", "#F4F4F4", "#1A1F2B", "#3DA9FF", "#B6FF3C"],
    },
}

DEFAULT = {
    "bg": "white",
    "text": "#111827",
    "grid": "rgba(17,24,39,0.10)",
    "palette": [
        "#5B8FF9", "#F6BD16", "#5AD8A6", "#E8684A",
        "#945FB9", "#6DC8EC", "#9270CA", "#FF9D4D",
    ],
}

if preset_name and preset_name not in PRESETS:
    print(f"render_chart: unknown preset {preset_name!r}; valid: {sorted(PRESETS)}", file=sys.stderr)
    sys.exit(2)

tokens = PRESETS[preset_name] if preset_name else DEFAULT
PALETTE = tokens["palette"]

def _pick(i):
    return PALETTE[i % len(PALETTE)]

def _alpha(hex_color, alpha_hex):
    if hex_color.startswith("#") and len(hex_color) == 7:
        return hex_color + alpha_hex
    return hex_color

if kind == "pie":
    for ds in datasets:
        ds.setdefault("backgroundColor", [_pick(i) for i in range(len(ds.get("data", [])))])
elif kind == "line":
    for i, ds in enumerate(datasets):
        c = _pick(i)
        ds.setdefault("borderColor", c)
        ds.setdefault("backgroundColor", _alpha(c, "33"))
        ds.setdefault("tension", 0.2)
else:
    for i, ds in enumerate(datasets):
        c = _pick(i)
        ds.setdefault("backgroundColor", c)
        ds.setdefault("borderColor", c)

def _plugins(title):
    p = {
        "title":  { "display": True, "text": title, "color": tokens["text"] },
        "legend": { "labels": { "color": tokens["text"] } },
    }
    if brand_url:
        # QuickChart-specific plugin — documented under "backgroundImageUrl"
        # at https://quickchart.io/documentation/add-watermark/
        p["backgroundImageUrl"] = brand_url
    return p

def _scales():
    return {
        "x": { "ticks": { "color": tokens["text"] },
               "grid":  { "color": tokens["grid"] } },
        "y": { "ticks": { "color": tokens["text"] },
               "grid":  { "color": tokens["grid"] } },
    }

title_text = spec.get("title", "")
if kind == "horizontal_bar":
    cfg = { "type": "bar",
            "data": data,
            "options": { "indexAxis": "y",
                         "plugins": _plugins(title_text),
                         "scales":  _scales() } }
elif kind == "line":
    cfg = { "type": "line",
            "data": data,
            "options": { "elements": { "line": { "tension": 0.2 } },
                         "plugins": _plugins(title_text),
                         "scales":  _scales() } }
elif kind == "pie":
    cfg = { "type": "pie", "data": data,
            "options": { "plugins": _plugins(title_text) } }
elif kind == "scatter":
    cfg = { "type": "scatter", "data": data,
            "options": { "plugins": _plugins(title_text),
                         "scales":  _scales() } }
elif kind == "table":
    cfg = { "type": "table", "data": data, "options": { "title": title_text } }
else:  # bar
    cfg = { "type": "bar", "data": data,
            "options": { "plugins": _plugins(title_text),
                         "scales":  _scales() } }

bg = tokens["bg"]
bg_param = urllib.parse.quote(bg, safe="")

# Encode once to decide GET vs POST. Threshold 1900 leaves headroom under the
# common 2048-byte URL limit after counting the other query params.
cfg_json = json.dumps(cfg, ensure_ascii=False)
encoded = urllib.parse.quote(cfg_json, safe="")
get_url = (f"https://quickchart.io/chart?c={encoded}"
           f"&width=800&height=400&backgroundColor={bg_param}&version=4")

if len(get_url) <= 1900:
    print(f"GET {get_url}")
else:
    body = {
        "chart": cfg,
        "width": 800, "height": 400,
        "version": 4,
        "backgroundColor": bg,
        "format": "png",
    }
    fd, body_path = tempfile.mkstemp(prefix="render-chart-body-", suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(body, f, ensure_ascii=False)
    print(f"POST https://quickchart.io/chart {body_path}")
PY
)

method="${plan%% *}"
rest="${plan#* }"

case "$method" in
  GET)
    actual_url="$rest"
    body_path=""
    ;;
  POST)
    actual_url="${rest%% *}"
    body_path="${rest##* }"
    ;;
  *)
    echo "render_chart: internal error — unexpected plan method: $plan" >&2; exit 4 ;;
esac

if [[ "$print_url_only" -eq 1 ]]; then
  echo "$actual_url"
  [[ -n "$body_path" ]] && rm -f "$body_path"
  exit 0
fi

# Fetch the PNG.
tmp="$(mktemp)"
if [[ "$method" == "GET" ]]; then
  if ! curl -fsSL --max-time 30 "$actual_url" -o "$tmp"; then
    rm -f "$tmp"
    echo "render_chart: HTTP/curl failed (GET) for $actual_url" >&2
    exit 4
  fi
else
  if ! curl -fsSL --max-time 30 -X POST -H "Content-Type: application/json" \
      --data @"$body_path" "$actual_url" -o "$tmp"; then
    rm -f "$tmp" "$body_path"
    echo "render_chart: HTTP/curl failed (POST) for $actual_url" >&2
    exit 4
  fi
  rm -f "$body_path"
fi
mkdir -p "$(dirname "$out")"
mv "$tmp" "$out"

# Write meta sidecar. For POST renders, quickchart_url is left null so the
# Notion push code skips the image block (no stable external URL) — the
# locally-rendered PNG is authoritative.
meta="${out%.png}.meta.json"
python3 - "$spec" "$actual_url" "$meta" "$preset" "$method" "$brand_image" <<'PY'
import json, sys, pathlib, datetime
spec   = json.load(open(sys.argv[1], "r", encoding="utf-8"))
url    = sys.argv[2]
meta   = pathlib.Path(sys.argv[3])
preset = sys.argv[4] or None
method = sys.argv[5]
brand  = sys.argv[6] or None
out = {
    "id": spec.get("id"),
    "title": spec.get("title"),
    "spec": spec,
    "preset": preset,
    "brand_image": brand,
    "render_method": method,
    "rendered_at": datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z",
    "quickchart_url": url if method == "GET" else None,
    "source_ids": sorted({ e.get("source_id") for e in (spec.get("evidence") or []) if e.get("source_id") is not None }),
}
meta.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
PY

echo "$out"
