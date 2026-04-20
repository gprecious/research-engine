#!/usr/bin/env bash
# Render a chart-spec JSON via QuickChart.io.
#
# Usage:
#   render_chart.sh <spec.json> <out.png>         # fetch PNG + write <out>.meta.json
#   render_chart.sh --print-url <spec.json>       # print constructed URL, exit 0
#
# Exit codes: 0 ok · 2 bad args · 3 validation failed · 4 HTTP/curl failed
set -euo pipefail

print_url_only=0
if [[ "${1:-}" == "--print-url" ]]; then
  print_url_only=1
  shift
fi

spec="${1:-}"
out="${2:-}"

[[ -f "$spec" ]] || { echo "render_chart: spec not found: $spec" >&2; exit 2; }
if [[ "$print_url_only" -eq 0 ]]; then
  [[ -n "$out" ]] || { echo "render_chart: out path required" >&2; exit 2; }
fi

# Build the Chart.js config + URL via python (jq-only JSON construction for nested
# objects gets verbose). Echoes URL on stdout.
url=$(python3 - "$spec" <<'PY'
import json, sys, urllib.parse, re

spec_path = sys.argv[1]
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

# Build Chart.js config.
if kind == "horizontal_bar":
    cfg = { "type": "bar",
            "data": data,
            "options": { "indexAxis": "y",
                         "plugins": { "title": { "display": True, "text": spec.get("title","") } } } }
elif kind == "line":
    cfg = { "type": "line",
            "data": data,
            "options": { "elements": { "line": { "tension": 0.2 } },
                         "plugins": { "title": { "display": True, "text": spec.get("title","") } } } }
elif kind == "pie":
    cfg = { "type": "pie", "data": data,
            "options": { "plugins": { "title": { "display": True, "text": spec.get("title","") } } } }
elif kind == "scatter":
    cfg = { "type": "scatter", "data": data,
            "options": { "plugins": { "title": { "display": True, "text": spec.get("title","") } } } }
elif kind == "table":
    cfg = { "type": "table", "data": data, "options": { "title": spec.get("title","") } }
else:  # bar
    cfg = { "type": "bar", "data": data,
            "options": { "plugins": { "title": { "display": True, "text": spec.get("title","") } } } }

encoded = urllib.parse.quote(json.dumps(cfg, ensure_ascii=False), safe="")
print(f"https://quickchart.io/chart?c={encoded}&width=800&height=400&backgroundColor=white&version=4")
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
python3 - "$spec" "$url" "$meta" <<'PY'
import json, sys, pathlib, datetime
spec  = json.load(open(sys.argv[1], "r", encoding="utf-8"))
url   = sys.argv[2]
meta  = pathlib.Path(sys.argv[3])
out = {
    "id": spec.get("id"),
    "title": spec.get("title"),
    "spec": spec,
    "rendered_at": datetime.datetime.utcnow().isoformat(timespec="seconds") + "Z",
    "quickchart_url": url,
    "source_ids": sorted({ e.get("source_id") for e in (spec.get("evidence") or []) if e.get("source_id") is not None }),
}
meta.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
PY

echo "$out"
