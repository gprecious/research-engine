#!/usr/bin/env python3
"""
judge.py — LLM-as-judge for bench runs.

Modes:
  --dry-run                                 # print built prompt, no claude call
  --from-fixture <file>                     # use canned JSON instead of claude
  --topic-dir <dir> --topic-id <id>         # judge a single topic
  --all --runs-dir bench/runs/<date>        # judge every topic under date
  --self-check --topic-dir <dir>            # feed RE as both A and B, expect equal scores
  --judge-model <model>                     # default claude-sonnet-4-6

Writes <topic-dir>/judge.json validated against bench/schemas/judge.schema.json.
Stdlib only (no pip deps).
"""
from __future__ import annotations
import argparse
import json
import os
import random
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROMPT_FILE = ROOT / "lib" / "judge_prompt.md"

DEFAULT_MODEL = "claude-sonnet-4-6"


def build_cross_mode_prompt(text_a: str, text_b: str, topic_id: str) -> str:
    return (
        f"## Topic id (for your reference only)\n{topic_id}\n\n"
        f"## report A\n\n{text_a}\n\n## report B\n\n{text_b}\n"
    )


def build_repro_prompt(run1: str, run2: str, topic_id: str) -> str:
    return (
        f"## Reproducibility judgment\n"
        f"Topic: {topic_id}\n\n"
        f"## report run1\n\n{run1}\n\n## report run2\n\n{run2}\n"
    )


def call_claude(prompt: str, model: str) -> str:
    """Invoke claude -p with the prompt; return stdout. Stdlib subprocess only."""
    system = PROMPT_FILE.read_text(encoding="utf-8")
    proc = subprocess.run(
        ["claude", "-p", "--model", model, "--system-prompt", system, prompt],
        capture_output=True, text=True, timeout=600,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"claude -p exited {proc.returncode}: {proc.stderr[:500]}")
    return proc.stdout


def parse_strict_json(s: str) -> dict:
    """Parse first JSON object found in s. Raises on failure."""
    start = s.find("{")
    end = s.rfind("}")
    if start < 0 or end < 0 or end <= start:
        raise ValueError(f"no JSON object in response: {s[:200]}")
    return json.loads(s[start : end + 1])


def detect_blindness_break(s: str) -> bool:
    """Return True if response contains label-leak keywords."""
    bad = ("research-engine", "plugin", "subagent", "vanilla")
    return any(b in s.lower() for b in bad)


def judge_topic(
    topic_dir: Path,
    topic_id: str,
    *,
    dry_run: bool = False,
    fixture: Path | None = None,
    judge_model: str = DEFAULT_MODEL,
    self_check: bool = False,
) -> dict:
    re1 = (topic_dir / "re" / "run1" / "output.md").read_text(encoding="utf-8")
    base1 = (topic_dir / "baseline" / "run1" / "output.md").read_text(encoding="utf-8")

    # In self_check, both A and B are the SAME RE output — expect ~equal scores.
    if self_check:
        cand_a, cand_b = ("re", re1), ("re", re1)
    else:
        labelled = [("re", re1), ("baseline", base1)]
        random.shuffle(labelled)
        cand_a, cand_b = labelled[0], labelled[1]

    prompt = build_cross_mode_prompt(cand_a[1], cand_b[1], topic_id)

    if dry_run:
        print(prompt)
        return {}

    if fixture:
        raw = fixture.read_text(encoding="utf-8")
    else:
        raw = call_claude(prompt, judge_model)

    parsed = parse_strict_json(raw)
    blind = not detect_blindness_break(raw)

    # In self_check, both labels collapse to "re" — store under re/baseline keys
    # so the judge.json schema still has both populated for downstream readers.
    if self_check:
        decoded = {"re": parsed["A"], "baseline": parsed["B"]}
    else:
        decoded = {cand_a[0]: parsed["A"], cand_b[0]: parsed["B"]}

    # Reproducibility — only when run2 exists for both modes (skipped in dry-run/fixture/self-check).
    repro = {"re": None, "baseline": None}
    for mode in ("re", "baseline"):
        run2_path = topic_dir / mode / "run2" / "output.md"
        run1_path = topic_dir / mode / "run1" / "output.md"
        if run2_path.exists() and run1_path.exists() and not (dry_run or fixture or self_check):
            r1 = run1_path.read_text(encoding="utf-8")
            r2 = run2_path.read_text(encoding="utf-8")
            r_raw = call_claude(build_repro_prompt(r1, r2, topic_id), judge_model)
            r_parsed = parse_strict_json(r_raw)
            repro[mode] = float(r_parsed.get("reproducibility")) if r_parsed.get("reproducibility") is not None else None

    out = {
        "topic_id": topic_id,
        "judge_model": judge_model if not fixture else "fixture",
        "judged_at": datetime.now(timezone.utc).isoformat(),
        "blind_label_map": {"A": cand_a[0], "B": cand_b[0]},
        "judge_blind": blind,
        "cross_mode": decoded,
        "reproducibility": repro,
    }

    out_path = topic_dir / "judge.json"
    out_path.write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
    return out


def main() -> int:
    p = argparse.ArgumentParser(description="LLM-as-judge for bench runs.")
    p.add_argument("--topic-dir", type=Path)
    p.add_argument("--topic-id")
    p.add_argument("--all", action="store_true")
    p.add_argument("--runs-dir", type=Path)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--from-fixture", type=Path)
    p.add_argument("--self-check", action="store_true")
    p.add_argument("--judge-model", default=DEFAULT_MODEL)
    args = p.parse_args()

    if args.all:
        if not args.runs_dir or not args.runs_dir.exists():
            print(f"--runs-dir {args.runs_dir} missing", file=sys.stderr)
            return 2
        for topic_dir in sorted(args.runs_dir.iterdir()):
            if topic_dir.is_dir() and (topic_dir / "re").exists():
                try:
                    judge_topic(topic_dir, topic_dir.name,
                                judge_model=args.judge_model)
                    print(f"OK {topic_dir.name}", file=sys.stderr)
                except Exception as e:
                    print(f"FAIL {topic_dir.name}: {e}", file=sys.stderr)
        return 0

    if not args.topic_dir or not args.topic_id:
        print("--topic-dir and --topic-id required (or use --all)", file=sys.stderr)
        return 2

    judge_topic(
        args.topic_dir,
        args.topic_id,
        dry_run=args.dry_run,
        fixture=args.from_fixture,
        judge_model=args.judge_model,
        self_check=args.self_check,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
