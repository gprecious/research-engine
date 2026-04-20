#!/usr/bin/env bash
# Render a chart-spec JSON via QuickChart.io.
#
# Usage:
#   render_chart.sh [--preset <name>] <spec.json> <out.png>   # fetch PNG + meta
#   render_chart.sh [--preset <name>] --print-url <spec.json> # print URL only
#
# --preset aligns chart colors with one of the 5 deck presets from
# lib/style_presets.md (dark-neon, editorial-serif, minimal-swiss,
# warm-neutral-teal, bold-geometric). Without --preset, falls back to the
# Okabe-Ito palette on a white background.
#
# Exit codes: 0 ok · 2 bad args · 3 validation failed · 4 HTTP/curl failed
set -euo pipefail

preset=""
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --preset)
      preset="${2:-}"; shift 2 ;;
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

# Build the Chart.js config + URL via python (jq-only JSON construction for nested
# objects gets verbose). Echoes URL on stdout.
url=$(python3 - "$spec" "$preset" <<'PY'
import json, sys, urllib.parse, re

spec_path = sys.argv[1]
preset_name = sys.argv[2] or None
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

# Collect values and assert each appears as a substring of some evidence quote.
data = spec.get("data") or {}
datasets = data.get("datasets") or []
quotes = " ||| ".join(e.get("quote_verbatim", "") for e in ev)
for ds in datasets:
    for v in ds.get("values", []):
        if isinstance(v, dict):  # scatter {x,y}
            nums = [v.get("x"), v.get("y")]
        else:
            nums = [v]
        for n in nums:
            if n is None:
                continue
            s = ("{:g}".format(n)) if isinstance(n, (int, float)) else str(n)
            if s not in quotes:
                # Try stringified float as-is too.
                if str(n) not in quotes:
                    errors.append(f"value {n!r} not found in any evidence quote_verbatim")

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(3)

# Chart.js v4 expects datasets[].data (not .values). Our spec contract uses
# .values for evidence-check clarity; remap here just before sending to QuickChart.
for ds in datasets:
    if "values" in ds:
        ds["data"] = ds.pop("values")

# Preset tokens — kept in sync with lib/style_presets.md. Hardcoded because there
# are only 5 and a markdown parser adds churn.
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

# Default (no preset) — preserve legacy Okabe-Ito on white.
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
    """Append 2-digit alpha to a #RRGGBB color. Non-hex colors returned as-is."""
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
        ds.setdefault("backgroundColor", _alpha(c, "33"))  # ~20% alpha fill
        ds.setdefault("tension", 0.2)
else:
    for i, ds in enumerate(datasets):
        c = _pick(i)
        ds.setdefault("backgroundColor", c)
        ds.setdefault("borderColor", c)

# Shared plugin block — titles, legends, and scale ticks inherit the preset's text color.
def _plugins(title):
    return {
        "title":  { "display": True, "text": title, "color": tokens["text"] },
        "legend": { "labels": { "color": tokens["text"] } },
    }

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

# QuickChart expects hex backgrounds URL-encoded (%23RRGGBB) or named colors.
bg = tokens["bg"]
bg_param = urllib.parse.quote(bg, safe="")
encoded = urllib.parse.quote(json.dumps(cfg, ensure_ascii=False), safe="")
print(f"https://quickchart.io/chart?c={encoded}&width=800&height=400&backgroundColor={bg_param}&version=4")
PY
)

if [[ "$print_url_only" -eq 1 ]]; then
  echo "$url"
  exit 0
fi

# Fetch the PNG.
tmp="$(mktemp)"
if ! curl -fsSL --max-time 30 "$url" -o "$tmp"; then
  rm -f "$tmp"
  echo "render_chart: HTTP/curl failed for $url" >&2
  exit 4
fi
mkdir -p "$(dirname "$out")"
mv "$tmp" "$out"

# Write meta sidecar.
meta="${out%.png}.meta.json"
python3 - "$spec" "$url" "$meta" "$preset" <<'PY'
import json, sys, pathlib, datetime
spec  = json.load(open(sys.argv[1], "r", encoding="utf-8"))
url   = sys.argv[2]
meta  = pathlib.Path(sys.argv[3])
preset = sys.argv[4] or None
out = {
    "id": spec.get("id"),
    "title": spec.get("title"),
    "spec": spec,
    "preset": preset,
    "rendered_at": datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z",
    "quickchart_url": url,
    "source_ids": sorted({ e.get("source_id") for e in (spec.get("evidence") or []) if e.get("source_id") is not None }),
}
meta.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
PY

echo "$out"
