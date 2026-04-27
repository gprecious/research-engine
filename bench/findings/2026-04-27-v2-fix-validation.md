# Re-bench validation — fixes applied (2026-04-27 v2)

## Procedure

After committing two P1 fixes (commit `bd5f1e4`):
1. arxiv-adapter requires PDF/HTML body fetch (not just abstract)
2. lib/report_sections.md enforces per-claim citation

…we patched the published plugin cache (`~/.claude/plugins/cache/gprecious-marketplace/research-engine/0.8.2/`) in-place with the worktree's fixed files, ran `/research --fresh --yes` for the two losing topics from the original matrix, judged each cross-mode against the unchanged original baseline run1 outputs, then restored the cache to the published v0.8.2 state.

## Quantitative results

| | RE words | RE citations | RE links |
|---|---|---|---|
| arxiv-mamba (original) | 1517 | 22 | 6 |
| arxiv-mamba (v2 fixed) | 1732 (+14%) | **48 (+118%)** | 4 |
| youtube-3blue1brown (original) | 987 | 22 | 4 |
| youtube-3blue1brown (v2 fixed) | 1613 (+63%) | **45 (+105%)** | 4 |

Citation count more than doubled on both topics. youtube also gained an explicit `## §7. 한계 / Limitations` section (the 81dfb13 fix took effect once the cache was patched).

## Cross-mode judge scores (RE_v2 vs unchanged Baseline run1)

| Topic | RE_v2 | Baseline | Δ_v2 | Δ_original | Swing |
|---|---|---|---|---|---|
| arxiv-mamba | 30 (cov 7, cit 8, dep 7, str 8) | 38 (cov 9, cit 10, dep 9, str 10) | **-8** | -16 | +8 |
| youtube-3blue1brown-gpt | 38 (cov 9, cit 10, dep 9, str 10) | 34 (cov 9, cit 8, dep 8, str 9) | **+4** | -16 | **+20** |

(Note: original Δ used a different blind A/B judge run — small score variance is normal. The structural pattern is what's stable.)

### youtube — fix decisively worked

Judge rationale on RE_v2 explicitly cited the two fixes:
- "**citations precisely map to video timestamps [1]**" → per-claim citation rule
- "structure is methodical (intent, TL;DR, core points, detailed sections, **limitations**, sources)" → §7 Limitations addition
- "**acknowledged scope limitations** (attention deferred, training absent, caption-based only)" → §7 Limitations addition (substantive content)

youtube swung from -16 (RE losing badly) to +4 (RE winning) on this single re-run. Net swing +20 points from original A/B to v2 A/B.

### arxiv — partial improvement, deeper issue surfaced

The arxiv-adapter PDF/HTML body fetch fix DID take effect — RE word count up 14%, citation count up 118%. But cross-mode judge swing was only +8 (from -16 to -8); RE_v2 still loses to baseline.

Judge rationale on RE_v2: *"Covers key concepts but omits significant experimental details (ablations, zero-shot downstream tasks, full related work taxonomy). Limited to 3 numbered sources. Structure is clean but content is condensed; **depth reduced by summarization**"*

Translation: the adapter fetched more body content, BUT the synthesis stage (commands/research.md Stage 5) compressed it during the merge-by-topic dedup. The synthesis pass over-summarizes.

## Projected full-matrix impact

If the other three topics' deltas are unchanged from the original matrix (blog +10, topic +4, github 0), the projected v2 full-matrix average:

| | Original | Projected v2 |
|---|---|---|
| arxiv | -16 | -8 |
| youtube | -16 | +4 |
| github | 0 | 0 |
| topic | +4 | +4 |
| blog | +10 | +10 |
| **avg Δ** | **-3.6** | **+2.0** |

**Net swing +5.6 points.** RE moves from underperforming to outperforming the baseline on average.

## Remaining gap → next P1

The arxiv +8 swing (vs youtube +20) tells us the per-claim citation rule and Limitations section helped, but the synthesis stage's compression is now the bottleneck for paper inputs. Next iteration:

**P1 (next) — Stage 5 (Synthesize) compression is too aggressive on dense scholarly inputs.**

Concretely, `commands/research.md` Stage 5 step 3 says: *"Merge findings by topic, not by adapter. Dedupe near-duplicate findings."* The "dedupe" step is where mechanism details (ablations, zero-shot downstream, related work) get collapsed into single lines.

Candidate fix: when input is `arxiv` or `huggingface` (academic), the dedupe pass should preserve adjacent fine-grained findings even when they share a parent topic — i.e., the §4 (상세 분석) section of the report should mirror the paper's own Method/Experiments/Limitations sub-structure, not collapse them.

Defer to a follow-up PR.

## Validation method limits

- Single-run swap (N=1 v2 each) — not full N=2. Repeat-variance unmeasured.
- Same blind A/B judge instance per topic. Different random seeds may move scores ±1.
- Cache patching is a hack to test pre-release fixes. The real validation is post-release re-bench against installed plugin.
- arxiv judge's "Limited to 3 numbered sources" comment may indicate the adapter is finding 3 sources but generating 48 citation occurrences — i.e., over-citing the same few sources. Citation **diversity** is a different axis we don't directly measure.

## Cache state

Cache restored to published 0.8.2. To validate these fixes against actually-installed plugins, bump the version and publish (or use the local-marketplace symlink pattern from the README's "local development install").
