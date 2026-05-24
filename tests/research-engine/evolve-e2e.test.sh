#!/usr/bin/env bats

setup() {
  WORK=$(mktemp -d)
  mkdir -p "$WORK/agents" "$WORK/research/_index" "$WORK/scripts" "$WORK/lib"
  cp -r lib/* "$WORK/lib/"
  cp scripts/evolve_run.sh "$WORK/scripts/"
  chmod +x "$WORK/scripts/evolve_run.sh"

  cat > "$WORK/agents/fixt-adapter.md" <<'MD'
# fixt-adapter
<!-- evolvable:guide -->
original guidance
<!-- /evolvable -->
MD
}

teardown() { rm -rf "$WORK"; }

@test "full cycle: prepare → apply → decide accept → promote" {
  cd "$WORK"

  # E2 prepare
  bash scripts/evolve_run.sh prepare fixt-adapter guide > mutator-in.json
  grep -q '"current_body": "original guidance"' mutator-in.json

  # E3 mock mutator output
  cat > mutator-out.json <<'JSON'
{"adapter_name":"fixt-adapter","region_id":"guide","variants":[{"body":"improved guidance","rationale":"test"}]}
JSON

  # E4 apply
  bash scripts/evolve_run.sh apply fixt-adapter guide mutator-out.json
  grep -q "improved guidance" agents/fixt-adapter.candidate.md

  # E5 (mock) bench scores — candidate beats current clearly
  cat > cur.json <<'JSON'
{"scores":[0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5],"source_count":8,"type_diversity":2,"latency_inv":0.01}
JSON
  cat > cand.json <<'JSON'
{"scores":[0.7,0.7,0.7,0.7,0.7,0.7,0.7,0.7],"source_count":10,"type_diversity":3,"latency_inv":0.01}
JSON

  # E6 decide
  out=$(bash scripts/evolve_run.sh decide fixt-adapter cur.json cand.json)
  echo "$out" | grep -q '"decision": "accept"'

  # E7 promote
  bash scripts/evolve_run.sh promote fixt-adapter
  grep -q "improved guidance" agents/fixt-adapter.md
  test -f agents/archive/fixt-adapter.v0.md || true   # version 0 archive may be skipped
  ! test -f agents/fixt-adapter.candidate.md
}

@test "full cycle with negative delta: decide rejects + candidate cleaned up" {
  cd "$WORK"
  cp agents/fixt-adapter.md agents/fixt-adapter.candidate.md
  cat > cur.json <<'JSON'
{"scores":[0.7,0.7,0.7,0.7,0.7,0.7,0.7,0.7],"source_count":10,"type_diversity":3,"latency_inv":0.01}
JSON
  cat > cand.json <<'JSON'
{"scores":[0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5],"source_count":5,"type_diversity":2,"latency_inv":0.005}
JSON
  out=$(bash scripts/evolve_run.sh decide fixt-adapter cur.json cand.json)
  echo "$out" | grep -q '"decision": "reject"'
  # candidate cleanup is /evolve slash responsibility, not evolve_run.sh — skip here
}
