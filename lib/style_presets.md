# Slide Style Presets

5 named visual presets for `visualizer-deck`. Each encodes background/surface/text/accent palette, a tested Google Fonts pairing, and a layout density rule. The deck agent **MUST** pick one and stick with it for the whole deck — no mixing across slides.

When intent is ambiguous, default to `minimal-swiss`. When the report is about data/metrics, prefer `dark-neon` or `bold-geometric`. When the report is reflective/long-form prose, prefer `editorial-serif` or `warm-neutral-teal`.

## Palette & typography contract

Every preset ships **5 colors** — `background`, `surface`, `text`, `accent1`, `accent2` — and a **2-family font pair** (`heading`, `body`). Body text must pass WCAG AA (4.5:1 against background), headlines 3:1.

| Preset | background | surface | text | accent1 | accent2 | heading font | body font | density | use when |
|---|---|---|---|---|---|---|---|---|---|
| `dark-neon` | `#0A0A0F` | `#14141C` | `#E6E8EF` | `#B6FF3C` (lime) | `#3DA9FF` (electric blue) | Space Grotesk 700 | IBM Plex Mono 300 | airy | dashboards, metric-heavy, modern tech product |
| `editorial-serif` | `#FAF7F2` | `#FFFFFF` | `#1B1B1E` | `#B54E3A` (terracotta) | `#2E5E4E` (forest) | DM Serif Display 400 | DM Sans 300 | generous | long-form research, reflective, policy |
| `minimal-swiss` | `#FFFFFF` | `#F3F3F3` | `#0D0D0D` | `#E63946` (signal red) | `#0D4F8B` (swiss blue) | Inter 800 | Inter 300 | dense | default for reports; clean, typography-first |
| `warm-neutral-teal` | `#F5EFE4` (wax paper) | `#FFFFFF` | `#2B241E` (cocoa) | `#1F8A8B` (transformative teal) | `#6B4F3B` (warm brown) | Fraunces 700 | Inter 400 | generous | human-centric, strategy, 2026 restorative palette |
| `bold-geometric` | `#0E1116` | `#1A1F2B` | `#F4F4F4` | `#FFCC00` (signal yellow) | `#FF4F4F` (signal red) | Archivo Black 900 | Archivo 400 | airy | launch decks, announcements, hero-slide heavy |

Hex values are the source of truth — the deck agent inlines these into the Marp `<style>` block. Do not round or substitute.

## Density rules

- `airy` — ≥ 120px vertical padding top/bottom, ≤ 5 bullets/slide, single chart dominant
- `generous` — ≥ 96px padding, ≤ 4 bullets/slide, large typographic breathing room
- `dense` — ≥ 64px padding, ≤ 6 bullets/slide, can pack 2 columns

## Marp theme template

Drop this block verbatim into the deck frontmatter, substituting the preset's tokens. The agent replaces `{{TOKEN}}` with the preset's values — **nothing else goes in the `<style>` block**.

```html
<style>
:root {
  --bg: {{background}};
  --surface: {{surface}};
  --text: {{text}};
  --a1: {{accent1}};
  --a2: {{accent2}};
  --heading-font: "{{heading_font}}", sans-serif;
  --body-font: "{{body_font}}", sans-serif;
}
section {
  background: var(--bg);
  color: var(--text);
  font-family: var(--body-font);
  font-size: 24pt;
  padding: {{padding_top}} {{padding_side}};
}
section h1, section h2, section h3 {
  font-family: var(--heading-font);
  color: var(--text);
  letter-spacing: -0.01em;
}
section.title h1 { font-size: 88pt; line-height: 0.95; }
section h1 { font-size: 44pt; }
section h2 { font-size: 32pt; }
section strong { color: var(--a1); }
section a { color: var(--a2); text-decoration: none; border-bottom: 2px solid var(--a2); }
section.lead { display: flex; flex-direction: column; justify-content: center; }
section.lead h1 { font-size: 80pt; }
section.divider { background: var(--a1); color: var(--bg); }
section.divider h1 { font-size: 96pt; }
section.bento { display: grid; grid-template-columns: 1.2fr 1fr; gap: 48px; }
section.chart-hero { padding: 48px; }
section.chart-hero img { width: 100%; height: auto; }
section::after { color: var(--text); opacity: 0.4; font-size: 12pt; }
</style>
```

`{{padding_top}}` / `{{padding_side}}`:
- `airy` → `120px 80px`
- `generous` → `96px 72px`
- `dense` → `64px 56px`

## Layout variants

The deck agent picks from 5 section classes and tags each slide's opening directive accordingly:

- `<!-- _class: title -->` — cover / first slide only
- `<!-- _class: lead -->` — section divider or single big assertion
- `<!-- _class: divider -->` — hard reset between parts; single word or short phrase
- `<!-- _class: bento -->` — two-column grid (e.g., assertion + evidence bullets)
- `<!-- _class: chart-hero -->` — single chart fills the slide; caption in `_footer`

Default (no class) = content slide with heading + bullets.

## Font loading

At the top of slides.md (above the Marp frontmatter is fine), include the Google Fonts `<link>`:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family={{heading_font_url}}:wght@{{heading_weight}}&family={{body_font_url}}:wght@{{body_weight}}&display=swap" rel="stylesheet">
```

Use URL-safe names (replace space with `+`): `Space+Grotesk`, `IBM+Plex+Mono`, `DM+Serif+Display`, `DM+Sans`, `Inter`, `Fraunces`, `Archivo+Black`, `Archivo`.
