#!/usr/bin/env python3
"""
lint_slides.py — deterministic rule check for a visualizer-deck slides.md

Usage:
  lint_slides.py <slides.md>

Prints a JSON object to stdout; always exits 0 so callers can decide severity.

The rules are the same ones encoded in agents/visualizer-deck.md and
lib/style_presets.md — this linter just catches violations without paying
for a visualizer-judge dispatch.

{
  "slide_count": 21,
  "violations": [
    { "slide": 7, "rule": "bullets_over_max", "detail": "8 bullets (max 6)" },
    { "slide": 12, "rule": "words_over_max",  "detail": "82 words (max 70)" },
    { "slide": 4,  "rule": "heading_noun_phrase", "detail": "'Sales Overview' has no verb" }
  ],
  "warnings": [
    { "slide": 21, "rule": "sources_class_exception", "detail": "section.sources intentionally violates 24pt body min (declared)" }
  ],
  "stats": {
    "layout_classes_used": ["title", "lead", "divider-num", "bento", "chart-hero", "sources"],
    "bullets_max_on_any_slide": 4,
    "words_max_on_any_slide": 62,
    "body_font_size_pt": 24,
    "font_families_declared": 2
  }
}
"""
import json
import re
import sys
from pathlib import Path

MAX_SLIDES = 25
MAX_BULLETS = 6
MAX_WORDS = 70
MIN_BODY_PT = 24
MIN_TITLE_PT = 80
MAX_FONT_FAMILIES = 2

# Heuristic: Korean verb/assertion detection.
# A Korean "assertion" heading typically ends with a verb conjugation
# (다/는다/한다/된다/이다/있다/없다/됨/함/자/요/냐/까) or a question/declaration marker.
# English assertion: contains any verb-like token (is|are|was|were|has|have|does|do|…).
KOREAN_VERB_ENDINGS = ("다", "한다", "된다", "는다", "이다", "있다", "없다", "요", "자", "야")
ENGLISH_VERBS = {
    "is","are","was","were","be","being","been",
    "has","have","had","having",
    "do","does","did","doing",
    "can","could","should","would","must","may","might","will","shall",
    "goes","go","goes","going","comes","come","came","makes","make","made",
    "show","shows","shift","shifts","shifted","close","closes","closed",
    "rise","rises","rose","fall","falls","fell","climb","climbs","climbed",
    "grew","grow","grows","drop","drops","dropped","drive","drives",
    "ship","ships","land","lands","win","wins","won","lose","loses","lost",
}

def detect_layout_class(block: str):
    """Scan HTML comment directives like <!-- _class: name --> anywhere in the slide block."""
    for line in block.splitlines():
        m = re.match(r"<!--\s*_class:\s*([\w-]+)\s*-->", line.strip())
        if m:
            return m.group(1)
    return None

def is_assertion(heading_text: str) -> bool:
    """Return True if heading looks like a full-sentence assertion (has a verb)."""
    stripped = heading_text.strip()
    if not stripped:
        return False
    # Strip Markdown emphasis markers that don't change semantics.
    bare = re.sub(r"[*`_]", "", stripped).strip()
    if not bare:
        return False

    # Single-character / pure-numeric / pure-symbol headings = divider-num style, OK.
    if len(bare) <= 3 or bare.replace(".", "").replace(" ", "").isdigit():
        return True

    # Korean heuristic: ends with a verb-like syllable/pattern.
    last2 = bare[-2:]
    last3 = bare[-3:]
    if any(bare.endswith(end) for end in KOREAN_VERB_ENDINGS):
        return True
    # Catch verb stems with common middle-of-phrase patterns
    # (e.g., "차지한다", "살아난다", "뚫는다", "가리킨다", "좁혀진다")
    if re.search(r"(한다|된다|는다|이다|있다|없다|가진다|진다|한다\b)", bare):
        return True

    # English heuristic: contains a verb-like token anywhere.
    tokens = re.findall(r"[A-Za-z]+", bare.lower())
    if tokens and any(t in ENGLISH_VERBS for t in tokens):
        return True

    return False

def split_slides(md: str):
    """Yield (slide_index, raw_block) for each slide (separated by `---` on its own line)."""
    lines = md.splitlines()
    # Skip YAML frontmatter.
    start = 0
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                start = i + 1
                break
    blocks = []
    buf = []
    for ln in lines[start:]:
        if ln.strip() == "---":
            blocks.append("\n".join(buf))
            buf = []
        else:
            buf.append(ln)
    if buf:
        blocks.append("\n".join(buf))
    # First block often contains the inline <style> preamble — still treat as slide 1.
    for i, block in enumerate(blocks, start=1):
        yield i, block

def count_bullets(block: str) -> int:
    return sum(1 for line in block.splitlines()
               if re.match(r"^\s*[-*+]\s", line))

def count_words(block: str) -> int:
    # Strip CSS <style> blocks, HTML comment directives, image tags, frontmatter remnants, headings markdown.
    stripped = re.sub(r"<style>.*?</style>", "", block, flags=re.DOTALL)
    stripped = re.sub(r"<!--.*?-->", "", stripped, flags=re.DOTALL)
    stripped = re.sub(r"<[^>]+>", "", stripped)
    stripped = re.sub(r"!\[.*?\]\(.*?\)", "", stripped)      # images
    stripped = re.sub(r"\[[^\]]*\]\([^)]*\)", "", stripped)  # links
    stripped = re.sub(r"[#*`_>]+", " ", stripped)
    tokens = re.findall(r"\S+", stripped)
    return len(tokens)

def extract_body_font_pt(md: str) -> int | None:
    """Parse the first `section { ... font-size: Npt; ... }` in the <style> block."""
    m = re.search(r"<style>(.*?)</style>", md, flags=re.DOTALL)
    if not m:
        return None
    css = m.group(1)
    # Match a `section { ... font-size: Npt ... }` rule (first one, which sets body default).
    m2 = re.search(r"(?:^|\s)section\s*\{[^}]*font-size:\s*(\d+)pt", css, flags=re.DOTALL)
    if m2:
        return int(m2.group(1))
    return None

def count_font_families(md: str) -> int:
    """Count unique Google Fonts families loaded via <link> tags."""
    families = set()
    for m in re.finditer(r"family=([^:&\"]+)", md):
        families.add(m.group(1))
    return len(families)

def extract_first_heading(block: str):
    for line in block.splitlines():
        m = re.match(r"^\s*(#{1,3})\s+(.+?)\s*$", line)
        if m:
            return m.group(1), m.group(2)
    return None, None

def lint(md_text: str) -> dict:
    violations = []
    warnings = []
    layout_classes = []
    bullets_hi = 0
    words_hi = 0

    blocks = list(split_slides(md_text))
    slide_count = len(blocks)
    if slide_count > MAX_SLIDES:
        violations.append({
            "slide": None,
            "rule": "slide_count_over_max",
            "detail": f"{slide_count} slides (max {MAX_SLIDES})"
        })

    body_pt = extract_body_font_pt(md_text)
    if body_pt is not None and body_pt < MIN_BODY_PT:
        violations.append({
            "slide": None,
            "rule": "body_font_under_min",
            "detail": f"body font-size {body_pt}pt (min {MIN_BODY_PT}pt in default section rule)"
        })

    n_families = count_font_families(md_text)
    if n_families > MAX_FONT_FAMILIES:
        violations.append({
            "slide": None,
            "rule": "too_many_font_families",
            "detail": f"{n_families} font families loaded (max {MAX_FONT_FAMILIES})"
        })

    for idx, block in blocks:
        klass = detect_layout_class(block)
        if klass:
            layout_classes.append(klass)

        # Section-class exemptions — sources is intentionally dense (31-entry ref list).
        if klass == "sources":
            warnings.append({
                "slide": idx,
                "rule": "sources_class_exception",
                "detail": "section.sources intentionally violates 24pt body min and 6-bullet cap (declared)"
            })
            continue

        bullets = count_bullets(block)
        if bullets > MAX_BULLETS:
            violations.append({
                "slide": idx,
                "rule": "bullets_over_max",
                "detail": f"{bullets} bullets (max {MAX_BULLETS})"
            })
        bullets_hi = max(bullets_hi, bullets)

        words = count_words(block)
        if words > MAX_WORDS:
            violations.append({
                "slide": idx,
                "rule": "words_over_max",
                "detail": f"{words} words (max {MAX_WORDS})"
            })
        words_hi = max(words_hi, words)

        level, heading = extract_first_heading(block)
        # Skip assertion check for divider/divider-num/title/lead (numerals or short phrases are fine).
        if klass in (None, "bento", "chart-hero") and heading:
            if not is_assertion(heading):
                violations.append({
                    "slide": idx,
                    "rule": "heading_noun_phrase",
                    "detail": f"'{heading}' reads as a label, not an assertion"
                })

    return {
        "slide_count": slide_count,
        "violations": violations,
        "warnings": warnings,
        "stats": {
            "layout_classes_used": sorted(set(layout_classes)),
            "bullets_max_on_any_slide": bullets_hi,
            "words_max_on_any_slide": words_hi,
            "body_font_size_pt": body_pt,
            "font_families_declared": n_families,
        },
    }

def main():
    if len(sys.argv) != 2:
        print("usage: lint_slides.py <slides.md>", file=sys.stderr)
        sys.exit(2)
    slides = Path(sys.argv[1])
    if not slides.is_file():
        print(f"lint_slides: file not found: {slides}", file=sys.stderr)
        sys.exit(2)
    result = lint(slides.read_text(encoding="utf-8"))
    print(json.dumps(result, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
