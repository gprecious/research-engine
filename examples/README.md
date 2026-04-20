# Reference Decks

Completed `visualizer-deck` outputs curated as **compositional references** — not content templates. The `visualizer-deck` agent is instructed to read 1–2 matching examples before generating a new deck (progressive disclosure).

Add a new file here whenever a rendered deck scores ≥90 on `visualizer-judge` and demonstrates a preset in a distinct content mode.

## Current examples

| File | Preset | Mode | Judge score | Notes |
|---|---|---|---|---|
| `dark-neon-dashboard.md` | `dark-neon` | metric-heavy research summary | 90/100 | Demonstrates: title / lead / divider / bento (3×) / chart-hero (4×) / default layout mix, assertion-evidence headings, `![bg fit]` chart slides with interpretive assertion above the image. |

## Gaps (open PRs welcome)

- `editorial-serif` reflective long-form example
- `minimal-swiss` dense-typography default example
- `warm-neutral-teal` strategy/human-centric example
- `bold-geometric` launch/announcement example

Each new example should be a real, judge-validated deck — do not hand-author placeholders. Compose by running `/research-visualize --slides --judge --preset <name>` on a real research session and promoting the result.
