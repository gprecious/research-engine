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
