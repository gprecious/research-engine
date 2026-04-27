# Report Section Templates

Used by `commands/research.md` during Stage 5 (Synthesize). Include only the sections whose inputs exist; omit empty sections instead of printing "N/A".

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
