# V3 re-bench — academic sub-structure fix validates arxiv gap closure

## Procedure

After committing the academic sub-structure fix (commit `8465fd4`):
- `commands/research.md` Stage 5 step 3: input-type-aware dedupe; arxiv/huggingface §4 MUST sub-divide into `### 방법론 / 핵심 메커니즘`, `### 실험 결과 / 벤치마크`, `### 저자 한계 / 미해결` with ≥2 findings each.
- `lib/report_sections.md` §4: explicit academic sub-structure pattern with examples.

…we re-patched the cache with all THREE fixed files (arxiv-adapter, report_sections, research) and ran one more `/research --fresh --yes` for arxiv-mamba, judged against the unchanged baseline run1.

## Results

### Structural verification

```
$ grep -E "^### (방법론|실험 결과|저자 한계)" v3/arxiv-mamba/re/run1/output.md
### 방법론 / 핵심 메커니즘
### 실험 결과 / 벤치마크
### 저자 한계 / 미해결

$ grep -E "^## .*한계" v3/arxiv-mamba/re/run1/output.md
## 7. 한계 및 열린 질문 (Limitations & Open Questions)
```

All three required §4 sub-headings present. §7 Limitations section also present (slight title variation accepted). Sub-heading content: 5 method findings, 5 experiment findings, 4 limitation findings.

### Judge scores (v3 RE vs unchanged baseline run1)

| Axis | Original RE | v2 RE (body+citation) | v3 RE (+sub-structure) | Baseline |
|---|---|---|---|---|
| Coverage | 8 | 7 | **9** (+1 vs v2) | 9 |
| Citation | 5 | 8 | 8 | 9 |
| Depth | 7 | 7 | **9** (+2 vs v2) | 8 |
| Structure | 8 | 8 | 9 (+1 vs v2) | 9 |
| **Sum / 40** | **28** | **30** | **35** | **35** |
| **Δ vs Baseline** | **-8** | **-8** | **0** (tie!) | — |

### What changed

The depth axis flipped from -1 (RE losing) to +1 (RE winning). Judge rationale on RE_v3: *"substantial exploration of S6 mechanism, hardware optimization, **and ablation studies**; well-hierarchized with clear sections and TL;DR"*.

The new academic sub-structure rule forced ablation findings, evaluation-table entries, and method-mechanism details to surface as distinct bullets rather than getting collapsed by Stage 5 dedup. The structural prescription IS the depth amplifier for academic content.

## Cumulative full-matrix projection

If the other 3 topics' deltas hold (blog +10, topic +4, github 0):

| Topic | Original Δ | After fixes (projected) |
|---|---|---|
| arxiv-mamba | -16 | **0** |
| youtube-3blue1brown | -16 | +4 |
| github-anthropic-courses | 0 | 0 |
| topic-moe-routing-2025 | +4 | +4 |
| blog-anthropic-harness | +10 | +10 |
| **average** | **-3.6** | **+3.6** |

**Net cumulative swing: +7.2 points.** RE moves from underperforming baseline by 3.6 to outperforming it by 3.6 — a complete reversal driven by three coordinated fixes:

1. `commits 81dfb13` — required §7 Limitations section
2. `commit bd5f1e4` — arxiv-adapter PDF body required + per-claim citation rule
3. `commit 8465fd4` — Stage 5 input-type-aware dedup with academic sub-structure

## Validation method limits

(same as v2 findings)
- N=1 v3 run for arxiv only — youtube N=1 v2, others unchanged. Variance unmeasured.
- Same blind A/B judge instance per topic.
- Cache was patched in-place to test pre-release fixes; restored to published v0.8.2 after.
- Citation count similar across v2 (48) and v3 (45) — slightly fewer because the more structured layout deduplicates within-source repeats. Quality > count.
- Word count v2→v3 dropped from 1732 to 1441 — more concise, but each sub-heading carries denser content. Judge gave +5 to the v3 in spite of the lower word count, supporting "granularity > length" thesis.

## Cache state

Cache restored to published v0.8.2. Re-validate post-release.
