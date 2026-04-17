# Acceptance: YouTube URL

**Input:** `/research https://www.youtube.com/watch?v=dQw4w9WgXcQ`

## Expected behavior

- [ ] Stage 2 preview completes in ≤30s.
- [ ] Stage 3 asks 1–3 dynamic questions grounded in the video's title/description.
- [ ] After I answer, Stage 4 dispatches youtube-adapter + (optionally) arxiv/github/context7 based on preview hints.
- [ ] Stage 5 writes:
  - [ ] `research/<date>-<slug>/README.md`
  - [ ] `research/<date>-<slug>/transcript.md`
  - [ ] `research/<date>-<slug>/sources.json`
  - [ ] `research/<date>-<slug>/intent.json`
  - [ ] `research/<date>-<slug>/cache/preview-*.json`
- [ ] README contains: Intent, TL;DR, 핵심 포인트, 상세 분석, 챕터별 요약, 타임코드 인용, 인용/원문, 연관 자료, Sources.
- [ ] Every factual bullet has at least one `[n]` citation.
- [ ] Timecodes look like `[12:34]` and match transcript positions.
- [ ] If anything failed, "수집 실패" section is present.
