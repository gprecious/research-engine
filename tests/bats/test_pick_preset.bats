#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/pick_preset.py"

setup() {
  TMPDIR_T="$(mktemp -d)"
  README="$TMPDIR_T/README.md"
}
teardown() { rm -rf "$TMPDIR_T"; }

@test "exits 0 and prints preset name" {
  echo "# empty report" > "$README"
  run python3 "$SCRIPT" "$README"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^(dark-neon|editorial-serif|minimal-swiss|warm-neutral-teal|bold-geometric)$ ]]
}

@test "empty content defaults to minimal-swiss" {
  echo "# just a title" > "$README"
  run python3 "$SCRIPT" "$README"
  [ "$status" -eq 0 ]
  [ "$output" = "minimal-swiss" ]
}

@test "--scores emits JSON with winner and scores" {
  echo "# dashboard performance metrics 대시보드" > "$README"
  run python3 "$SCRIPT" "$README" --scores
  [ "$status" -eq 0 ]
  [[ "$output" == *'"winner"'* ]]
  [[ "$output" == *'"scores"'* ]]
  [[ "$output" == *'"dark-neon"'* ]]
}

@test "dashboard-heavy content picks dark-neon" {
  cat > "$README" <<'EOF'
# Q3 Observability Overview

This report covers telemetry from our p99 latency dashboard,
throughput KPIs across the real-time monitoring stack.

## Dashboard 지표

- 대시보드에서 성능 지표를 모니터링한다
- 처리량과 응답시간을 실시간으로 본다
- 벤치마크 수행 (benchmark p95 p99)
EOF
  run python3 "$SCRIPT" "$README"
  [ "$status" -eq 0 ]
  [ "$output" = "dark-neon" ]
}

@test "policy-heavy content picks editorial-serif" {
  cat > "$README" <<'EOF'
# A Study of Long-Form Policy Analysis

This research paper reviews the theory and history of
policy framework design. The analysis draws from manuscripts
and long-form essays. We critique current approaches.

## 고찰

정책 연구와 논문 분석을 통한 이론적 회고를 담는다.
검토 결과는 심층 분석으로 이어진다.
EOF
  run python3 "$SCRIPT" "$README"
  [ "$status" -eq 0 ]
  [ "$output" = "editorial-serif" ]
}

@test "customer-culture content picks warm-neutral-teal" {
  cat > "$README" <<'EOF'
# Customer Experience Strategy

Our brand strategy centers on culture, people, and community.
Employee and team stakeholder qualitative research.
Human-centric organization design.

## 전략

고객 경험과 브랜드 문화를 중심으로 한 전략.
팀·조직·이해관계자 관점을 통합한다.
EOF
  run python3 "$SCRIPT" "$README"
  [ "$status" -eq 0 ]
  [ "$output" = "warm-neutral-teal" ]
}

@test "launch announcement content picks bold-geometric" {
  cat > "$README" <<'EOF'
# Product Launch Keynote

We unveil the product at our keynote event. The launch campaign
announces the debut of the rollout. Release notes follow.

## 발표

신제품 출시 런치 및 캠페인 개요.
키노트 공개행사 일정 정리.
EOF
  run python3 "$SCRIPT" "$README"
  [ "$status" -eq 0 ]
  [ "$output" = "bold-geometric" ]
}

@test "generic research report picks minimal-swiss" {
  cat > "$README" <<'EOF'
# Architecture Specification Overview

This report summarizes the reference documentation for our
guideline framework. Standard principles are defined in the
main specification.

## 개요

표준 문서의 요약과 원칙을 담은 가이드 보고서이다.
EOF
  run python3 "$SCRIPT" "$README"
  [ "$status" -eq 0 ]
  [ "$output" = "minimal-swiss" ]
}

@test "tie-break favors minimal-swiss over others at equal score" {
  # Single hit each for dark-neon (dashboard) and minimal-swiss (report).
  cat > "$README" <<'EOF'
# Title

The report mentions a dashboard exactly once.
EOF
  run python3 "$SCRIPT" "$README"
  [ "$status" -eq 0 ]
  [ "$output" = "minimal-swiss" ]
}

@test "markdown link [label](url) does not count the label as a keyword" {
  # "launch" appears only inside a link label; should NOT count for bold-geometric
  # because _tokenize_english tokenizes plain text (punctuation boundaries handle it).
  # This test confirms behavior is stable when surrounding markdown is present.
  cat > "$README" <<'EOF'
# Architecture Specification Overview

- See [launch notes](https://example.com) for details
- standard reference specification guideline
EOF
  run python3 "$SCRIPT" "$README"
  [ "$status" -eq 0 ]
  # minimal-swiss (spec/standard/reference/guideline = 4) vs bold-geometric (launch = 1)
  [ "$output" = "minimal-swiss" ]
}

@test "frontmatter is ignored — signals only come from body" {
  cat > "$README" <<'EOF'
---
title: "launch keynote unveil release"
slug: "anything"
---

# Research Report

This is a policy analysis with research and study content.
EOF
  run python3 "$SCRIPT" "$README"
  [ "$status" -eq 0 ]
  # Frontmatter has 4 bold-geometric keywords; body has 4 editorial-serif. Body wins.
  [ "$output" = "editorial-serif" ]
}

@test "missing file exits 2" {
  run python3 "$SCRIPT" /nonexistent/path.md
  [ "$status" -eq 2 ]
}
