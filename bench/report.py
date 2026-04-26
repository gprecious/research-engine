#!/usr/bin/env python3
"""
report.py — render bench/runs/<date>/report.md from results.json.

Usage:
  report.py --results <path/to/results.json> --out <path/to/report.md>

Stdlib only.
"""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path

LIMITATIONS = """\
## Limitations

- LLM-as-judge with same model family (Claude): potential self-favoring bias.
- N=2 trials per (topic, mode): too small for statistical confidence intervals.
- 5 topics = 1 per category: weak generalization across diverse content within a category.
- `baseline_prompt` phrasing is sensitive — small wording changes can move scores.
"""


def render(results: dict) -> str:
    lines: list[str] = []
    agg = results.get("aggregate", {})
    lines.append(f"# research-engine vs Claude Code bench — {results.get('bench_date', '?')}\n")
    lines.append("## Executive summary\n")
    lines.append(
        f"- RE average: **{agg.get('re_avg')}**\n"
        f"- Baseline average: **{agg.get('baseline_avg')}**\n"
        f"- Δ (RE − baseline): **{agg.get('delta_avg')}**\n"
        f"- Judge model: `{results.get('judge_model', '?')}`\n"
        f"- Model under test: `{results.get('model_under_test', '?')}`\n"
    )

    by_axis = agg.get("by_axis", {})
    if by_axis:
        lines.append("\n```mermaid\nxychart-beta\n  title \"Per-axis averages (0–10)\"\n  x-axis [coverage, citation, depth, structure, reproducibility]\n")
        re_vals = [by_axis.get(a, {}).get("re", 0) for a in ("coverage","citation","depth","structure","reproducibility")]
        base_vals = [by_axis.get(a, {}).get("baseline", 0) for a in ("coverage","citation","depth","structure","reproducibility")]
        lines.append(f"  y-axis 0 --> 10\n  bar {re_vals}\n  bar {base_vals}\n```\n")

    lines.append("\n## Per-topic detail\n")
    lines.append("| topic | category | RE | baseline | Δ |\n|---|---|---|---|---|")
    for t in results.get("topics", []):
        lines.append(f"| {t['id']} | {t.get('category','?')} | {t.get('re',{}).get('weighted_total','?')} | {t.get('baseline',{}).get('weighted_total','?')} | {t.get('delta','?')} |")
    lines.append("")

    lines.append("\n## Improvement opportunities\n")
    opportunities: list[str] = []
    for t in results.get("topics", []):
        delta = t.get("delta") or 0
        if delta <= 5:
            opportunities.append(f"- **{t['id']}** (Δ={delta}): {t.get('judge_rationale','')}")
    for axis, d in by_axis.items():
        if (d.get("re") or 10) <= 6:
            opportunities.append(f"- Axis **{axis}** RE avg = {d.get('re')} → research-engine weak spot")
    if not opportunities:
        opportunities.append("- (No obvious weak spots in this run; consider widening topic set.)")
    lines.extend(opportunities)
    lines.append("")

    lines.append(LIMITATIONS)
    return "\n".join(lines)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--results", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    args = p.parse_args()

    data = json.loads(args.results.read_text(encoding="utf-8"))
    args.out.write_text(render(data), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
