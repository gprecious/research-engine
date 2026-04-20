# Reference Decks

Completed `visualizer-deck` outputs curated as **compositional references** — not content templates. The `visualizer-deck` agent is instructed to read 1–2 matching examples before generating a new deck (progressive disclosure).

Add a new file here whenever a rendered deck scores ≥90 on `visualizer-judge` and demonstrates a preset in a distinct content mode.

## Current examples

| File | Preset | Mode | Judge score | Notes |
|---|---|---|---|---|
| `dark-neon-dashboard.md` | `dark-neon` | metric-heavy research summary | 90/100 | Demonstrates: title / lead / **divider-num (3×, 200pt numeral flourish)** / bento (3×, 4-bullet cap) / chart-hero (4×) / **sources (14pt 2-column ref list)** layout mix, assertion-evidence headings, `![bg fit]` chart slides with interpretive assertion above the image, every body `[n]` marker resolved against sources.json (linter-verified). |
| `minimal-swiss-research.md` | `minimal-swiss` | typography-first research report | linter-clean (0 violations) | Same 31-source research content as above but in Swiss-minimal discipline — single `Inter` family with 300/800 weights (`font_families_declared: 1`), 64×56 dense padding, red accent bar on left edge of divider slides (not numeral flourish), `bullets_max_on_any_slide: 6` (under the dense-preset cap). Shows how the same content flexes across presets. |

## Gaps (open PRs welcome)

- `editorial-serif` reflective long-form example
- `warm-neutral-teal` strategy/human-centric example
- `bold-geometric` launch/announcement example

Each new example should be a real, judge-validated deck — do not hand-author placeholders. Compose by running `/research-visualize --slides --judge --preset <name>` on a real research session and promoting the result.
