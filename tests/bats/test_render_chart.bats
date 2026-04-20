#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/render_chart.sh"

setup() {
  TMPDIR_T="$(mktemp -d)"
  SPEC="$TMPDIR_T/spec.json"
  OUT="$TMPDIR_T/chart.png"
}

teardown() { rm -rf "$TMPDIR_T"; }

valid_spec() {
  cat > "$SPEC" <<'EOF'
{
  "id": "c1",
  "title": "MMLU 비교",
  "kind": "bar",
  "rationale": "테스트용",
  "data": {
    "labels": ["A", "B"],
    "datasets": [ { "label": "MMLU", "values": [88.7, 91.2] } ]
  },
  "evidence": [
    { "source_id": 1, "quote_verbatim": "A scored 88.7 on MMLU" },
    { "source_id": 2, "quote_verbatim": "B scored 91.2 on MMLU" }
  ],
  "axis": { "x": "모델", "y": "점수" }
}
EOF
}

@test "--print-url emits a quickchart URL for valid spec" {
  valid_spec
  run "$SCRIPT" --print-url "$SPEC"
  [ "$status" -eq 0 ]
  [[ "$output" == https://quickchart.io/chart?c=* ]]
  [[ "$output" == *"width=800"* ]]
}

@test "rejects spec with missing evidence" {
  cat > "$SPEC" <<'EOF'
{ "id": "c1", "title": "x", "kind": "bar",
  "data": { "labels": ["A"], "datasets": [ { "label": "s", "values": [5] } ] },
  "evidence": [] }
EOF
  run "$SCRIPT" --print-url "$SPEC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"evidence"* ]]
}

@test "rejects spec with number not in any evidence quote" {
  cat > "$SPEC" <<'EOF'
{ "id": "c1", "title": "x", "kind": "bar",
  "data": { "labels": ["A"], "datasets": [ { "label": "s", "values": [99.9] } ] },
  "evidence": [ { "source_id": 1, "quote_verbatim": "completely different text" } ] }
EOF
  run "$SCRIPT" --print-url "$SPEC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"99.9"* ]]
}

@test "rejects spec with disallowed kind" {
  cat > "$SPEC" <<'EOF'
{ "id": "c1", "title": "x", "kind": "bogus",
  "data": { "labels": ["A"], "datasets": [ { "label": "s", "values": [1] } ] },
  "evidence": [ { "source_id": 1, "quote_verbatim": "1" } ] }
EOF
  run "$SCRIPT" --print-url "$SPEC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"kind"* ]]
}

@test "horizontal_bar produces bar type with indexAxis=y" {
  cat > "$SPEC" <<'EOF'
{ "id": "c1", "title": "x", "kind": "horizontal_bar",
  "data": { "labels": ["A"], "datasets": [ { "label": "s", "values": [1.0] } ] },
  "evidence": [ { "source_id": 1, "quote_verbatim": "1.0" } ] }
EOF
  run "$SCRIPT" --print-url "$SPEC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"indexAxis"* ]]
}

@test "fails when spec file missing" {
  run "$SCRIPT" --print-url "/nonexistent/spec.json"
  [ "$status" -ne 0 ]
}

@test "URL contains Chart.js-compatible datasets[].data (not .values)" {
  # Regression test: Chart.js v4 requires datasets[].data, but our spec contract
  # uses datasets[].values for evidence-check readability. render_chart.sh must
  # rename before sending to QuickChart so the rendered PNG isn't blank.
  valid_spec
  run "$SCRIPT" --print-url "$SPEC"
  [ "$status" -eq 0 ]
  # Decode the URL and check the datasets key at the JSON level.
  decoded="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1].split("c=")[1].split("&")[0]))' "$output")"
  [[ "$decoded" == *'"data":'* || "$decoded" == *'"data": '* ]]
  # The "values" key must NOT appear inside datasets[].
  python3 -c '
import json, sys
cfg = json.loads(sys.argv[1])
for ds in cfg["data"]["datasets"]:
    assert "data" in ds, f"dataset missing data key: {ds}"
    assert "values" not in ds, f"dataset still has values key: {ds}"
' "$decoded"
}

@test "bar datasets receive distinct palette colors" {
  valid_spec
  run "$SCRIPT" --print-url "$SPEC"
  [ "$status" -eq 0 ]
  decoded="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1].split("c=")[1].split("&")[0]))' "$output")"
  python3 -c '
import json, sys
cfg = json.loads(sys.argv[1])
ds = cfg["data"]["datasets"]
for d in ds:
    c = d.get("backgroundColor")
    assert isinstance(c, str) and c.startswith("#"), f"missing/invalid backgroundColor: {d}"
colors = [d["backgroundColor"] for d in ds]
assert len(set(colors)) == len(colors), f"duplicate colors across datasets: {colors}"
' "$decoded"
}

@test "pie chart receives per-slice backgroundColor array" {
  cat > "$SPEC" <<'EOF'
{ "id": "cp", "title": "pie test", "kind": "pie",
  "data": { "labels": ["A","B","C"], "datasets": [ { "label": "s", "values": [1, 2, 3] } ] },
  "evidence": [ { "source_id": 1, "quote_verbatim": "A=1 B=2 C=3" } ] }
EOF
  run "$SCRIPT" --print-url "$SPEC"
  [ "$status" -eq 0 ]
  decoded="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1].split("c=")[1].split("&")[0]))' "$output")"
  python3 -c '
import json, sys
cfg = json.loads(sys.argv[1])
bg = cfg["data"]["datasets"][0]["backgroundColor"]
assert isinstance(bg, list), f"pie expects array of colors, got {type(bg)}"
assert len(bg) == 3, f"expected 3 slice colors, got {len(bg)}"
for c in bg:
    assert c.startswith("#")
' "$decoded"
}
