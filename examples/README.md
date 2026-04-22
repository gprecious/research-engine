# Reference Decks

Completed `visualizer-deck` outputs curated as **compositional references** — not content templates. The `visualizer-deck` agent is instructed to read 1–2 matching examples before generating a new deck (progressive disclosure).

Add a new file here whenever a rendered deck scores ≥90 on `visualizer-judge` and demonstrates a preset in a distinct content mode.

## Current examples

| File | Preset | Mode | Judge score | Notes |
|---|---|---|---|---|
| `dark-neon-dashboard.md` | `dark-neon` | metric-heavy research summary | 90/100 | title / lead / **divider-num (3×, 200pt numeral flourish)** / bento (3×, 4-bullet cap) / chart-hero (4×) / **sources (14pt 2-col ref list)** layout mix, assertion-evidence headings, `![bg fit]` chart slides with interpretive assertion above the image. |
| `minimal-swiss-research.md` | `minimal-swiss` | typography-first research report | 0 violations | Swiss-minimal discipline — single `Inter` family (300/800), 64×56 dense padding, red accent bar on left edge of divider slides (not numeral flourish), `bullets_max_on_any_slide: 6` (dense-preset cap). |
| `editorial-serif-research.md` | `editorial-serif` | long-form reflective research | 0 violations | Magazine feel — DM Serif Display titles + DM Sans body on wax-paper `#FAF7F2`, terracotta h1 underline accent (96px × 3px bar) instead of numeral flourish, dividers use forest-green section label over terracotta left bar, 4-bullet generous cap. |
| `warm-neutral-teal-research.md` | `warm-neutral-teal` | strategy / human-centric | 0 violations | Fraunces + Inter pairing on warm `#F5EFE4`, **teal as gentle highlight** (strong tags only) not flood, warm-brown accent2 as divider structural bar (24px left border), 4-bullet generous cap. |
| `bold-geometric-research.md` | `bold-geometric` | launch / announcement | 0 violations | Archivo Black 900 + Archivo 400 on near-black `#0E1116`, oversized 104–112pt title/divider type, **yellow divider background** with black inverse text for hard breaks, red accent on links only, 5-bullet airy cap (one slide uses 6 — under the universal hard cap but mildly over the airy density rule). |

## Gaps

All 5 presets have a first-pass reference deck. Future additions should demonstrate **distinct content modes** not yet shown — e.g., a YouTube-transcript research session, an arXiv-paper-centric deck with heavy math, an M&A / strategy deck, a product launch deck with hero imagery. Drop them next to the existing files when available.

Each new example should be a real, judge-validated deck — do not hand-author placeholders. Compose by running `/research-visualize --slides --judge --preset <name>` on a real research session and promoting the result if lint is clean and judge ≥85.
