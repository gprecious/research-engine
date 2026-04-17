# Adapter Contract

Every adapter subagent MUST return a SINGLE fenced JSON block matching the schema below. The orchestrator parses the first such block from the subagent's reply.

## Schema

```json
{
  "adapter": "youtube | arxiv | github | blog | context7 | huggingface | community",
  "status": "ok | partial | failed",
  "sources": [
    {
      "id": "s1",
      "type": "youtube-captions | arxiv-paper | github-repo | blog-page | ...",
      "url": "https://...",
      "title": "...",
      "meta": { "anything": "json" }
    }
  ],
  "findings": [
    {
      "text": "concise factual statement in Korean (or original for quotes)",
      "source_ids": ["s1", "s2"],
      "timecode": "12:34",      // optional, YouTube only
      "quote": "optional verbatim excerpt"
    }
  ],
  "artifacts": {
    "transcript_md": "...",    // optional — full transcript as markdown
    "chapters": [
      {"title": "Intro", "start": "0:00", "end": "2:15", "summary": "..."}
    ],
    "related": [
      {"kind": "paper|repo|blog|docs", "url": "...", "title": "..."}
    ]
  },
  "failures": [
    {"step": "captions_fetch", "error": "no_auto_captions", "url": "..."}
  ]
}
```

## Rules

- `adapter` MUST equal the adapter's own name.
- `sources[].id` MUST be unique within the adapter's response. The orchestrator re-numbers across adapters.
- `findings[].source_ids` MUST reference ids declared in the same response's `sources`.
- If nothing was retrievable, return `status: "failed"` with empty arrays and populated `failures`.
- Partial success (some steps failed, some succeeded) → `status: "partial"`.
- The orchestrator must be able to parse the JSON with `jq`; no trailing commas, no comments.
- All free-form text in `findings[].text` is written in Korean (per report language rule); quotes stay in original language.

## Output envelope

The subagent may prepend a short human-readable status line, but the JSON block MUST be:

````
```json
{ ... }
```
````

(a single fenced block; no stray code fences).
