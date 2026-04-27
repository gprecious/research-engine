# arxiv-adapter secondary references — validation (2026-04-28)

## Procedure

After committing the 3-bucket secondary references restructure (commit `a8727e1`):
- Bucket a: author-cited prior art (2-4 entries)
- Bucket b: forward citations / follow-ups via HF paper-page or Semantic Scholar (2-4 entries)
- Bucket c: implementations + venue discussion via paper-page linked repo + firecrawl search (1-4 entries)

Patched cache (v0.9.0 content + new arxiv-adapter overlay), ran one fresh `/research --fresh --yes` for arxiv-mamba, judged against fresh baseline.

## Results

| Run | Coverage | Citation | Depth | Structure | Sum/40 | vs Baseline |
|---|---|---|---|---|---|---|
| Original v0.8.2 RE | 8 | 5 | 7 | 8 | 28 | -8 (-16 normalized) |
| v0.9.0 RE | 8 | 6 | 7 | 9 | 30 | -7 (-12 normalized) |
| **v0.9.0 + secondary refs RE** | **9** | **8** | **9** | **8** | **34** | **0** (tie!) |
| Baseline | 8 | 9 | 8 | 9 | 34 | — |

**Cumulative arxiv swing: -16 → 0 (full +16 normalized).** Citation +3 vs v0.9.0, Depth +2 vs v0.9.0, Coverage +1.

Raw quantitative signals from RE:
- word_count: 1517/1546 (v0.8.2) → 990/958 (v0.9.0) → 1708 (with secondary)
- citation_count: 22/27 (v0.8.2) → 30 (v0.9.0) → **61** (+100% vs v0.9.0)
- external_link_count: 6/5 → 6 → **14** (+133% vs v0.9.0)

Judge rationale on the new RE: *"extensive secondary bucket organization (prior/follow-up/community) with 13 sources across arxiv/github/huggingface; Deeper mechanistic analysis of §3 selection logic (Theorem 1, RNN isomorphism, three mechanical effects)"*.

## What worked

The 3-bucket prompt forced the synthesizer to surface citations from **three distinct provenance lines**:
- Prior art: S4, H3, Hyena, RetNet, RWKV (cited as ancestor SSMs in §1)
- Forward: Mamba-2, VMamba (cited as successors in §5)
- Community: Falcon-Mamba-7B, mamba-130m-hf (cited as deployments in §6)

This matches what vanilla baselines do organically when given a paper URL — pull HF paper page citations + GitHub references — but now constrained by structural rules so RE doesn't over- or under-cite.

## Caveats

Single-run measurement. The original full matrix showed ±5-8 per-topic noise, so a single tied delta isn't conclusive. But the citation-count jump (+100%) and external-link jump (+133%) are not noise — those are direct measurements of the bucket prompt working.

## Next

Roll into v0.9.1 / v0.10.0 release. After release, full re-bench will tell if the arxiv tie holds at scale and whether other adapter categories benefit from a similar bucket pattern.
