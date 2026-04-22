#!/usr/bin/env python3
"""
pick_preset.py — deterministic preset selector based on README content signals.

Usage:
  pick_preset.py <README.md>                  # print preset name only
  pick_preset.py <README.md> --scores         # print JSON {preset: score, ...}

The 5 presets map to use-cases documented in lib/presets.json. Each preset has
a keyword bag; the picker counts hits in the README and returns the top-scoring
preset. Ties break toward `minimal-swiss` (the declared default for
typography-first reports).

Behavior contract:
- Always exits 0 with a preset name on stdout (one line, no newline prefix).
- Never requires network / LLM / heavy deps. Pure stdlib.
- Score is case-insensitive whole-word match. Korean tokens match verbatim.
- Tokens overlapping multiple presets are allowed; they contribute to each.
"""
import json
import re
import sys
from pathlib import Path

# Keyword profiles — English + Korean hints drawn from lib/presets.json use_when
# plus the 2026-trend research. Intentionally conservative: each hit is 1 point,
# no weighting, so the picker stays easy to reason about.
PROFILES = {
    "dark-neon": [
        # English
        "dashboard", "metric", "metrics", "kpi", "telemetry", "latency",
        "throughput", "performance", "benchmark", "percentile", "p95", "p99",
        "realtime", "real-time", "monitoring", "observability",
        # Korean
        "대시보드", "지표", "성능", "모니터링", "실시간", "처리량", "응답시간",
    ],
    "editorial-serif": [
        "research", "study", "analysis", "reflection", "history", "policy",
        "framework", "theory", "concept", "review", "paper", "manuscript",
        "essay", "critique", "long-form",
        "연구", "논문", "분석", "정책", "고찰", "이론", "회고", "검토",
    ],
    "minimal-swiss": [
        "report", "summary", "overview", "specification", "spec", "guideline",
        "standard", "principle", "documentation", "reference",
        "보고서", "요약", "개요", "표준", "원칙", "가이드", "문서",
    ],
    "warm-neutral-teal": [
        "strategy", "customer", "experience", "culture", "organization",
        "brand", "people", "team", "stakeholder", "qualitative", "human",
        "employee", "community",
        "전략", "고객", "경험", "문화", "조직", "브랜드", "팀", "사람", "이해관계자",
    ],
    "bold-geometric": [
        # Deliberately narrow — this preset is for launch/announcement decks,
        # not for any document that happens to mention "presentation".
        "launch", "announcement", "release", "keynote", "unveil", "debut",
        "rollout", "campaign",
        "런치", "발표회", "출시", "공개행사", "캠페인", "키노트",
    ],
}

# Deterministic tie-breaker order (first wins on tie).
TIE_BREAK = ["minimal-swiss", "editorial-serif", "dark-neon", "warm-neutral-teal", "bold-geometric"]


def _strip_frontmatter(md: str) -> str:
    """Remove YAML frontmatter if present; return body only."""
    lines = md.splitlines()
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return "\n".join(lines[i + 1:])
    return md


def _tokenize_english(text: str):
    """Lowercase alphanumeric tokens (hyphens preserved inside words)."""
    return re.findall(r"[a-z][a-z0-9\-]*", text.lower())


def _count_korean(text: str, kw: str) -> int:
    """Korean keywords have no word boundaries; count substring occurrences."""
    return text.count(kw)


def _is_korean(kw: str) -> bool:
    return any("\uac00" <= c <= "\ud7a3" for c in kw)


def score(md: str):
    body = _strip_frontmatter(md)
    english_tokens = _tokenize_english(body)
    english_set_count = {}
    for tok in english_tokens:
        english_set_count[tok] = english_set_count.get(tok, 0) + 1

    scores = {name: 0 for name in PROFILES}
    for preset, keywords in PROFILES.items():
        for kw in keywords:
            if _is_korean(kw):
                scores[preset] += _count_korean(body, kw)
            else:
                scores[preset] += english_set_count.get(kw.lower(), 0)
    return scores


def pick(scores: dict) -> str:
    max_score = max(scores.values())
    # If nothing matched at all, return the declared default.
    if max_score == 0:
        return "minimal-swiss"
    # Keep only top scorers, break ties via TIE_BREAK order.
    top = {name for name, v in scores.items() if v == max_score}
    for name in TIE_BREAK:
        if name in top:
            return name
    # Should not reach here, but fail safe.
    return "minimal-swiss"


def main():
    argv = sys.argv[1:]
    want_scores = False
    if argv and argv[0] == "--scores":
        want_scores = True
        argv = argv[1:]
    elif len(argv) >= 2 and argv[-1] == "--scores":
        want_scores = True
        argv = argv[:-1]

    if len(argv) != 1:
        print("usage: pick_preset.py <README.md> [--scores]", file=sys.stderr)
        sys.exit(2)

    path = Path(argv[0])
    if not path.is_file():
        print(f"pick_preset: file not found: {path}", file=sys.stderr)
        sys.exit(2)

    md = path.read_text(encoding="utf-8")
    scores = score(md)
    winner = pick(scores)

    if want_scores:
        print(json.dumps({"winner": winner, "scores": scores}, ensure_ascii=False, indent=2))
    else:
        print(winner)


if __name__ == "__main__":
    main()
