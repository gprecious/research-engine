# Acceptance: Follow-up session

**Preconditions:** A recent session exists (e.g., from the YouTube acceptance).

**Input:** `/research-followup "이 영상에서 언급된 첫 번째 논문의 저자는 누구?"`

## Expected

- [ ] Command auto-detects the latest slug.
- [ ] Answer cites sources by `[n]` from existing `sources.json` without refetching.
- [ ] A new entry is appended to `session.md` with an ISO timestamp.

**Input 2:** `/research-followup "이 영상과 비슷한 강연 하나 더 찾아줘"`

## Expected

- [ ] Dispatches 1 adapter (blog or youtube via WebSearch).
- [ ] New source is added to `sources.json` with next `n`.
- [ ] A `related/` file is written.
- [ ] `session.md` entry includes a "새 자료" subsection.
