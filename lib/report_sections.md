# Report Section Templates

Used by `commands/research.md` during Stage 5 (Synthesize). Include only the sections whose inputs exist; omit empty sections instead of printing "N/A".

## Citation enforcement (applies to §3, §4, §5)

Every factual claim sentence in the body MUST end with at least one `[n]` marker tying the claim to a source. "Factual claim" means: any sentence that asserts a number, mechanism, named entity, dated event, comparison, or causal relationship. "Decorative" mass-marker citations at the end of long paragraphs are not acceptable — bind the marker to the specific claim sentence.

Rules:
- Connecting / framing sentences (e.g., "이 절에서는…", "다음으로 살펴볼 것은…") may omit `[n]`.
- Direct quotes always carry the source `[n]`, plus `(timecode)` for YouTube.
- If a single sentence draws on multiple sources, append all relevant ids: `... 이라고 보고됨 [3] [7]`.
- If the synthesizer cannot find a source for a claim, the claim must be removed — never leave an unsourced factual statement in the report.

This rule is absolute for §3 (핵심 포인트), §4 (상세 분석), §5 (인용 / 원문). It is recommended but not required for §1 (분석 목적), §2 (요약), and §7 (한계 / 미해결).

Optional claim-review sections (§4.5 검증 매트릭스, §7.5 누락 관점 / 후속 질문) are rendered only when `claim_review.json` exists and has non-empty inputs. Claim rows in §4.5 still follow the same `[n]` source binding rule.

## Frontmatter (required)

```markdown
---
title: "{{report_title}}"
slug: "{{slug}}"
created: "{{iso_date}}"
input: "{{original_input}}"
input_type: "{{classified_type}}"
intent_mode: "user | assumed"
---
```

## §1. 분석 목적 (Intent)

```markdown
## 분석 목적 (Intent)

**사용자 답변**
- 용도: {{intent.purpose}}
- 집중: {{intent.focus}}
- 배경지식: {{intent.audience_level}}

**엔진 해석**
{{intent.interpretation}}
```

If `intent_mode == "assumed"`, replace "사용자 답변" heading with "추정(assumed)".

## §2. 요약 (TL;DR)

```markdown
## 요약 (TL;DR)

{{tldr_paragraph_3_to_5_sentences}}
```

## §3. 핵심 포인트

```markdown
## 핵심 포인트

- {{point_1}} [{{src}}]
- {{point_2}} [{{src}}]
- ...
```

## §4. 상세 분석

```markdown
## 상세 분석

### {{subsection_title}}

{{body}} [{{src}}]
```

Structure subsections by topic, not by adapter. Merge findings that reinforce the same claim into one bullet with multiple `[src]` markers.

### Input-type-aware sub-structure (REQUIRED for academic inputs)

For `input_type: arxiv` or `huggingface`, §4 MUST use these sub-headings (omit a sub-heading only if the adapter returned zero findings for that bucket):

```markdown
## 상세 분석

### 방법론 / 핵심 메커니즘

- {{method_finding_1, with equation or named mechanism}} [{{src}}]
- {{method_finding_2}} [{{src}}]
- ...

### 실험 결과 / 벤치마크

- {{result_finding_1, with concrete number from paper body}} [{{src}}]
- {{result_finding_2, e.g., ablation showing X drops Y to Z}} [{{src}}]
- {{result_finding_3, e.g., zero-shot or downstream task numbers}} [{{src}}]
- ...

### 저자 한계 / 미해결

- {{limitation_finding_1, marked by adapter as 저자가 명시한 한계}} [{{src}}]
- ...
```

Minimum 2 fine-grained findings per sub-heading when content is available. Do NOT collapse method details, ablation rows, or evaluation-table entries into single summary lines — granularity IS the depth signal.

For `github` / `context7` (code/docs), prefer sub-headings like `### 구조 / 모듈`, `### 활성도 / 메인테이닝`, `### 사용 패턴` when each has 2+ findings.

For `youtube` / `blog` / `community`, free-form sub-headings by topic remain appropriate.

## §4.5 검증 매트릭스 (optional — only when `claim_review.json` exists with non-empty `claims`)

Render one row per key claim from `claim_review.json`. Every claim row still binds its `[n]` markers to specific sources (citation rule § 위 applies). Omit the whole section when `claim_review.json` is absent or `claims` is empty.

```markdown
## 검증 매트릭스

| 주장 | 근거 | 반증 | 상태 | 신뢰도 |
|---|---|---|---|---|
| {{claim}} | {{supporting_sources → [n] [n]}} | {{challenging_sources → [n] or —}} | {{citation_status}} | {{confidence}} |
```

For any claim with a non-null `corrected_text`, add a line beneath the table: `- ⚠️ {{claim 요약}} → 수정: {{corrected_text}} [n]`. Claims with `citation_status: unsupported`/`contradicted` MUST already have been dropped or softened in §3/§4 during synthesis — the matrix documents *why*.

## §5. 인용 / 원문

```markdown
## 인용 / 원문

> {{quote_verbatim}}
> — [{{src}}] {{optional_timecode}}
```

## §6. 연관 자료

```markdown
## 연관 자료

### 논문
- [{{paper_title}}]({{url}}) — {{one_line_why_relevant}}

### 레포
- [{{owner/repo}}]({{url}}) — {{one_line_why_relevant}}

### 블로그 / 문서
- [{{title}}]({{url}}) — {{one_line_why_relevant}}
```

## §7. 한계 / 미해결 (Limitations) — required, ≥2 bullets

```markdown
## 한계 / 미해결

- {{limitation_1}}: {{one_sentence_why_or_open_question}}
- {{limitation_2}}: ...
```

What belongs here:
- Known weaknesses of the work analyzed (methodological gaps, dataset coverage, generalization concerns) when the input is a paper/post.
- Open questions the source raises but does not answer.
- Items the engine could not verify (e.g., closed-source benchmarks, claims unsupported by primary sources).

What does NOT belong:
- Adapter fetch failures — those go in §8 (수집 실패).
- Generic disclaimers ("this is a summary, not the original paper").

If the engine truly cannot identify any limitation after reviewing the body, write a single bullet `- (검토 결과 명시적 한계 없음 — 후속 검증 권장)` rather than omitting the section.

## §7.5 누락 관점 / 후속 질문 (optional — only when `claim_review.json` has non-empty `missing_lenses` or any `needs_followup` claim)

```markdown
## 누락 관점 / 후속 질문

- **{{missing_lens.lens}}** — {{missing_lens.why}} (후속: `{{followup_query}}`)
- (needs_followup claim) {{claim 요약}} → {{왜 후속이 필요한지}}
```

Omit the section entirely when there are no missing lenses and no `needs_followup` claims. This section feeds a later `/research-followup`; it is NOT a substitute for the §7 한계 section.

## §8. 수집 실패 (Failures) — include only if non-empty

```markdown
## 수집 실패 (Failures)

- `{{adapter}}` / `{{step}}` — {{error_summary}}
```

## §9. Sources

```markdown
## Sources

1. **{{title}}** — {{url}} (adapter: `{{adapter}}`, fetched: {{iso}})
2. ...
```

## YouTube-only supplemental sections

Insert between §4 and §5 when `input_type == "youtube"`.

```markdown
## 챕터별 요약

### {{chapter_title}} ({{start}} – {{end}})

{{3_to_5_sentence_summary}}
```

```markdown
## 타임코드 인용

- **[{{mm:ss}}]** "{{verbatim}}"
```

And `transcript.md` is written as a separate file — not inlined.
