#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/lint_slides.py"

setup() {
  TMPDIR_T="$(mktemp -d)"
  SLIDES="$TMPDIR_T/slides.md"
}
teardown() { rm -rf "$TMPDIR_T"; }

clean_deck() {
  cat > "$SLIDES" <<'EOF'
---
marp: true
theme: default
paginate: true
---

<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@700&family=IBM+Plex+Mono:wght@300" rel="stylesheet">

<style>
section { font-size: 24pt; }
</style>

<!-- _class: title -->

# 얇은 스택이 텍스트 과다를 낳는다

---

## 4축 rubric으로 덱을 평가한다

- Design Quality [1]
- Originality [1]
- Craft [1]
- Functionality [1]
EOF
}

@test "exits 0 and emits JSON" {
  clean_deck
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"slide_count"'* ]]
  [[ "$output" == *'"violations"'* ]]
}

@test "clean deck has zero violations" {
  clean_deck
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"violations": []'* ]]
}

@test "flags bullet-count over max" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; }</style>

## 7 bullet 슬라이드를 허용하지 않는다

- a
- b
- c
- d
- e
- f
- g
EOF
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"bullets_over_max"'* ]]
  [[ "$output" == *'"7 bullets (max 6)"'* ]]
}

@test "flags word-count over max" {
  # Assemble a slide with > 70 content words.
  big_body="$(printf '가나다 %.0s' {1..120})"
  cat > "$SLIDES" <<EOF
---
marp: true
---
<style>section { font-size: 24pt; }</style>

## 아주 긴 문단이 들어왔다

${big_body}
EOF
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"words_over_max"'* ]]
}

@test "flags noun-phrase heading" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; }</style>

## Sales Overview

- a
- b
EOF
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"heading_noun_phrase"'* ]]
  [[ "$output" == *"Sales Overview"* ]]
}

@test "accepts Korean assertion heading (ends with 다)" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; }</style>

## Q3 매출이 전년비 23% 성장했다

- 증거 [1]
EOF
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"heading_noun_phrase"'* ]]
}

@test "accepts English assertion heading (has verb)" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; }</style>

## Revenue grew 23% year over year

- evidence [1]
EOF
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"heading_noun_phrase"'* ]]
}

@test "section.sources class is a declared exception (warning, not violation)" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; } section.sources { font-size: 14pt; }</style>

<!-- _class: sources -->

# Sources

1. a
2. b
3. c
4. d
5. e
6. f
7. g
EOF
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"sources_class_exception"'* ]]
  [[ "$output" != *'"bullets_over_max"'* ]]
}

@test "flags body font-size under 24pt" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 18pt; }</style>

## 본문 14pt는 가독성 하한을 깬다

- a
EOF
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"body_font_under_min"'* ]]
}

@test "flags slide count over 25" {
  # 26 minimal slides
  {
    echo "---"
    echo "marp: true"
    echo "---"
    echo "<style>section { font-size: 24pt; }</style>"
    for i in $(seq 1 26); do
      echo
      echo "---"
      echo
      echo "## 슬라이드 ${i}는 테스트 대상이다"
      echo "- x"
    done
  } > "$SLIDES"
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"slide_count_over_max"'* ]]
}

@test "flags more than 2 font families loaded" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk&family=Inter&family=Fraunces" rel="stylesheet">
<style>section { font-size: 24pt; }</style>

## 3개 폰트는 너무 많다

- a
EOF
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"too_many_font_families"'* ]]
}

@test "missing file exits 2" {
  run python3 "$SCRIPT" /nonexistent/path.md
  [ "$status" -eq 2 ]
}

@test "source marker resolution: zero violations when every [n] exists" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; }</style>

## 본문 24pt는 2026 기본선이다

- 근거 1 [1]
- 근거 2 [3]
EOF
  cat > "$TMPDIR_T/sources.json" <<'EOF'
{ "sources": [
  { "n": 1, "title": "a", "url": "https://a" },
  { "n": 2, "title": "b", "url": "https://b" },
  { "n": 3, "title": "c", "url": "https://c" }
] }
EOF
  run python3 "$SCRIPT" "$SLIDES" "$TMPDIR_T/sources.json"
  [ "$status" -eq 0 ]
  [[ "$output" != *"source_marker_unresolved"* ]]
  [[ "$output" == *'"source_markers_referenced": ['* ]]
}

@test "source marker resolution: flags [n] missing from sources.json" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; }</style>

## 본문 24pt는 2026 기본선이다

- 근거 1 [1]
- 근거 2 [99]
EOF
  cat > "$TMPDIR_T/sources.json" <<'EOF'
{ "sources": [
  { "n": 1, "title": "a", "url": "https://a" }
] }
EOF
  run python3 "$SCRIPT" "$SLIDES" "$TMPDIR_T/sources.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"source_marker_unresolved"'* ]]
  [[ "$output" == *"[99]"* ]]
}

@test "source marker resolution: handles grouped markers [1,2,3]" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; }</style>

## 본문 24pt는 2026 기본선이다

- 근거 묶음 [1,2,99]
EOF
  cat > "$TMPDIR_T/sources.json" <<'EOF'
{ "sources": [
  { "n": 1, "title": "a", "url": "https://a" },
  { "n": 2, "title": "b", "url": "https://b" }
] }
EOF
  run python3 "$SCRIPT" "$SLIDES" "$TMPDIR_T/sources.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[99]"* ]]
  # [1] and [2] are valid — must not appear as unresolved
  # This line asserts the specific unresolved detail only contains 99.
  [[ "$output" != *'"[1] referenced'* ]]
}

@test "source marker resolution: markdown link [label](url) not misidentified as a marker" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; }</style>

## Sources slide 스타일을 확정한다

1. [robonuggets/marp-slides](https://github.com/robonuggets/marp-slides) — 22 예제
EOF
  cat > "$TMPDIR_T/sources.json" <<'EOF'
{ "sources": [] }
EOF
  run python3 "$SCRIPT" "$SLIDES" "$TMPDIR_T/sources.json"
  [ "$status" -eq 0 ]
  # The label `robonuggets/marp-slides` is NOT a numeric marker and must not trigger the rule.
  [[ "$output" != *"source_marker_unresolved"* ]]
}

@test "heading_duplicated: flags two content slides sharing the same h2" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; }</style>

## 접근성은 숫자 린터로 강제한다

- a [1]

---

## 다른 논리가 그 사이에 있다

- b [1]

---

## 접근성은 숫자 린터로 강제한다

- duplicate heading [1]
EOF
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" == *"heading_duplicated"* ]]
  [[ "$output" == *"접근성은 숫자 린터로 강제한다"* ]]
}

@test "heading_duplicated: divider and sources repeats are allowed (no flag)" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; } section.divider { background: #f0f; }</style>

<!-- _class: divider -->
# 핵심 3가지

---

<!-- _class: divider -->
# 핵심 3가지
EOF
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" != *"heading_duplicated"* ]]
}

@test "bg_fit_outside_chart_hero: flags ![bg fit] on a default slide" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; }</style>

## 차트 비율이 어긋난다

![bg fit](figures/chart.png)
EOF
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bg_fit_outside_chart_hero"* ]]
}

@test "bg_fit_outside_chart_hero: allowed inside chart-hero" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; } section.chart-hero { padding: 48px; }</style>

<!-- _class: chart-hero -->

## 차트가 슬라이드를 채운다

![bg fit](figures/chart.png)
EOF
  run python3 "$SCRIPT" "$SLIDES"
  [ "$status" -eq 0 ]
  [[ "$output" != *"bg_fit_outside_chart_hero"* ]]
}

@test "malformed sources.json becomes a warning, not a violation" {
  cat > "$SLIDES" <<'EOF'
---
marp: true
---
<style>section { font-size: 24pt; }</style>

## 본문 24pt는 2026 기본선이다

- 근거 [1]
EOF
  echo "{ not json" > "$TMPDIR_T/broken.json"
  run python3 "$SCRIPT" "$SLIDES" "$TMPDIR_T/broken.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sources_json_unreadable"* ]]
}
