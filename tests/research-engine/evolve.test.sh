#!/usr/bin/env bats

setup() {
  WORK=$(mktemp -d)
  mkdir -p "$WORK/agents/archive" "$WORK/research/_index" "$WORK/docs/dreams" "$WORK/scripts"
  cp -r lib "$WORK/"
  cp scripts/evolve_run.sh "$WORK/scripts/"
  chmod +x "$WORK/scripts/evolve_run.sh"
}

teardown() { rm -rf "$WORK"; }

@test "prepare extracts evolvable region + recent dreams" {
  cat > "$WORK/agents/foo.md" <<'MD'
# foo
<!-- evolvable:bar -->
hello
<!-- /evolvable -->
MD
  cd "$WORK"
  out=$(bash scripts/evolve_run.sh prepare foo bar)
  echo "$out" | grep -q '"region_id": "bar"'
  echo "$out" | grep -q '"current_body": "hello"'
}

@test "apply writes candidate file with replaced region" {
  cat > "$WORK/agents/foo.md" <<'MD'
<!-- evolvable:bar -->
old
<!-- /evolvable -->
MD
  cat > "$WORK/mut.json" <<'JSON'
{ "variants": [ { "body": "new\nmulti", "rationale": "test" } ] }
JSON
  cd "$WORK"
  bash scripts/evolve_run.sh apply foo bar mut.json
  grep -q "new" "$WORK/agents/foo.candidate.md"
}

@test "decide writes ledger and prints decision" {
  cat > "$WORK/cur.json" <<'JSON'
{"scores": [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]}
JSON
  cat > "$WORK/cand.json" <<'JSON'
{"scores": [0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6], "source_count": 10, "type_diversity": 3, "latency_inv": 0.01}
JSON
  cd "$WORK"
  out=$(bash scripts/evolve_run.sh decide foo cur.json cand.json)
  echo "$out" | grep -q '"decision": "accept"'
  test -f "$WORK/research/_index/evolve-ledger.json"
}

@test "decide atomic write leaves no .tmp.* leftover" {
  cat > "$WORK/cur.json" <<'JSON'
{"scores":[0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5]}
JSON
  cat > "$WORK/cand.json" <<'JSON'
{"scores":[0.6,0.6,0.6,0.6,0.6,0.6,0.6,0.6],"source_count":10,"type_diversity":3,"latency_inv":0.01}
JSON
  cd "$WORK"
  bash scripts/evolve_run.sh decide foo cur.json cand.json >/dev/null
  test -f "$WORK/research/_index/evolve-ledger.json"
  ! ls "$WORK/research/_index/" | grep -E '\.tmp\.[0-9]+$'
}

@test "decide hold case does not mutate ledger" {
  cat > "$WORK/cur.json" <<'JSON'
{"scores": [0.50, 0.55, 0.45, 0.60, 0.40, 0.50, 0.55, 0.45]}
JSON
  cat > "$WORK/cand.json" <<'JSON'
{"scores": [0.55, 0.50, 0.50, 0.55, 0.45, 0.48, 0.52, 0.50], "source_count": 10, "type_diversity": 3, "latency_inv": 0.01}
JSON
  cd "$WORK"
  out=$(bash scripts/evolve_run.sh decide foo cur.json cand.json)
  echo "$out" | grep -q '"decision": "hold"'
  # Ledger should exist but have no adapter entry for foo (hold = no mutation)
  test -f "$WORK/research/_index/evolve-ledger.json"
  ! cat "$WORK/research/_index/evolve-ledger.json" | grep -q '"foo"'
}
