---
description: Deep research on a URL (YouTube/arXiv/GitHub/blog/docs) or topic keyword. Produces research/YYYY-MM-DD-<slug>/README.md.
argument-hint: "<URL or topic> [--yes] [--fresh] [--slug <name>]"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, WebFetch, WebSearch
---

## Inputs

`$ARGUMENTS` — raw argument string. Parse into:
- `target` (positional, required): URL or topic text
- `--yes`: skip Intent Q&A, engine infers
- `--fresh`: bypass cache
- `--slug <name>`: manual slug override

## Constants

- `${CLAUDE_PLUGIN_ROOT}` = plugin root, exported by Claude Code into each Bash tool invocation for commands owned by this plugin.
- `RESEARCH_DIR` = `<project_cwd>/research`
- Date today: !`date -u +%Y-%m-%d`

## Pipeline

Execute these stages **in order**. Do not skip stages.

### Stage 1 — Classify

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/classify_url.sh" "<target>"`. Store the result as `input_type`.

### Stage 2 — Preview

Branch by `input_type`:

- **youtube** → Pre-flight: `command -v yt-dlp >/dev/null || { echo "yt-dlp not installed. Install with: pipx install yt-dlp  (or)  brew install yt-dlp" >&2; exit 1; }`; also verify `ffmpeg` when visual/demo focus is likely. Then `bash "${CLAUDE_PLUGIN_ROOT}/scripts/yt_fetch.sh" metadata "<target>"` → parse title/description/chapters/selected_caption_lang. Extract roughly the first 5 minutes of transcript by running `yt_fetch.sh captions` into a temporary dir: captions are preferred, and when captions are absent the script attempts Groq Whisper fallback (`GROQ_API_KEY` from env or `~/.config/research-engine/`). For visual/demo/tutorial focus or missing transcript, run `yt_fetch.sh frames "<target>" "<tmp>/frames"` and preview the `frames.json` timecoded JPEG list.
- **arxiv** → invoke the `huggingface-skills:hugging-face-paper-pages` skill with the arXiv id to get title+abstract.
- **github** → `gh repo view <owner>/<repo> --json ...` + first 2 KB of README.
- **huggingface** → `hf` CLI card summary.
- **blog / community** → invoke the `firecrawl:firecrawl-scrape` skill (or `firecrawl:firecrawl` for more complex crawls) on the URL; take first 2 KB of markdown.
- **topic** → `WebSearch` with `<target>` and keep the top 10 result titles + snippets. (Top-10 widens the source pool so two consecutive runs share more overlap by chance, reducing the run-to-run source-set variance that bench reproducibility judges previously penalized.)

Write the preview to `RESEARCH_DIR/<tmp-slug>/cache/preview-<cache_key>.json` (create dir if needed). Compute `cache_key` via `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cache_key.sh" "<target>"`.

### Stage 2.5 — Memory Query (prior_knowledge 자동 조회)

After preview JSON is written, query memory for similar past sessions before moving to Stage 3:

```bash
# Build a target descriptor from preview-level info
TARGET_JSON=$(jq -nc \
  --arg t "<input_type>" \
  --arg p "<intent.purpose 후보 (preview title/description에서 추출, 또는 빈 문자열)>" \
  --arg sl "<slug 잠정>" \
  --argjson topics '[]' \
  '{input_type: $t, topics: $topics, intent: {purpose: $p}, slug: $sl}')

bash "${CLAUDE_PLUGIN_ROOT}/scripts/memory_query.sh" \
  --target-json "${TARGET_JSON}" \
  --top-k 5 \
  --self-slug "<slug>" \
  > "<report_dir>/cache/memory.json"
```

The query runs BEFORE Stage 3 Intent Q&A. At this point you only have preview-level info — that's enough for similarity matching. The result `cache/memory.json` is consumed in Stage 4 dispatch as `prior_knowledge`.

If `cache/memory.json` is `{"similar_sessions":[],"dream_insights":[]}` (no priors), proceed normally — memory is optional and silently absent on first runs.

### Stage 3 — Intent Q&A

Compute `slug`:
- If `--slug` provided, use it.
- Otherwise run `slugify.sh` on the preview title (or on `<target>` for topic mode).
- Prefix with today's date: `${DATE}-${SLUG}`. Handle collision by appending `-2`, `-3`.

Finalize the report directory `<report_dir> = RESEARCH_DIR/<date>-<slug>/`. If a tmp-slug dir was created in Stage 2, move its contents in.

Then:

- If `--yes` was set, SKIP interactive Q&A. Derive an `intent` object from the preview (your best judgment). Record `intent_mode: "assumed"` in the report frontmatter.
- Otherwise, generate **1–3 dynamic questions** grounded in the preview content and ASK THEM in the chat. Wait for the user's reply. Structure their reply into `intent = { purpose, focus, audience_level, notes }`. Record `intent_mode: "user"`.
- If preview failed, fall back to the 3 fixed questions in `lib/intent_questions_fallback.md`.

Save intent to `<report_dir>/intent.json`.

**실행 모델**: `/research` 슬래시 커맨드는 Intent Q&A 응답을 받을 때까지 블로킹. 사용자는 터미널에서 응답을 타이핑하고, 그 뒤 Stage 4로 진행.

### Stage 4 — Plan & Parallel Dispatch

Apply `superpowers:dispatching-parallel-agents`. Build a work plan:

- **Primary adapter** for the `input_type` (youtube → youtube-adapter, arxiv → arxiv-adapter, etc.). Topic mode has NO primary; it fans out to all tier-1 adapters.
- **Secondary adapters** driven by the preview:
  - If preview mentions arXiv IDs → arxiv-adapter
  - If preview mentions repo URLs → github-adapter
  - If preview mentions library names → context7-adapter (libraries list in the prompt)
  - If preview mentions HF assets → huggingface-adapter
  - If preview links HN/Reddit threads → community-adapter (pass `thread_urls`)
  - For topic mode → all tier-1 + community-adapter with `topic_query`.

Dispatch each adapter with a single Agent call, parallel (issue all Agent tool calls in one assistant message). Before dispatching, dispatcher reads <report_dir>/cache/memory.json once and includes the same JSON as the `prior_knowledge` field in every adapter's input. Per-adapter prompt template:

```
You are dispatched as the <adapter-name> subagent for research session <slug>.

Inputs:
  <JSON of {url|targets|libraries|thread_urls, intent, cache_dir, slug, fresh, prior_knowledge}>

prior_knowledge (when non-empty) contains the contents of <report_dir>/cache/memory.json — similar past sessions and active dream insights from the research-engine memory layer. Treat it as HINTS only, not verified facts. If you reuse a finding from prior_knowledge, you MUST cite the prior session/dream via its slug or run_id in your `findings[].sources[]` or in a `failures[]` note. Do not blindly copy prior findings — fresh sources still take priority. If prior_knowledge is empty `{similar_sessions:[],dream_insights:[]}`, proceed normally.

Return a single fenced JSON block per lib/adapter_contract.md. Do not include anything after the JSON block.
```

Timeout per adapter: 5 minutes — except youtube-adapter: 20 minutes (AV-first media download + Whisper transcription scale with video length; no length cap per spec). Configured implicitly by the agent runtime; do NOT actively retry beyond the single dispatch. If an adapter returns non-JSON or malformed JSON, record it as a failure and continue.

### Stage 5 — Synthesize & Persist

**⚠️ DO-NOT-SKIP CHECKLIST.** This stage has **8 numbered steps**. You MUST complete ALL of them before declaring Stage 5 done. Do NOT treat the Markdown file writes (steps 2–6) as "the whole stage" — steps 7 and 8 are mandatory side effects (Notion mirror + final user message format). Before marking Stage 5 complete, verify three artifacts exist: `sources.json` contains `output_notion_url`, `README.md` starts with a `> 📒 Notion:` line under the frontmatter, and your final user-facing message line includes the Notion URL.

1. Collect adapter outputs. Re-number source ids across adapters into a single one-indexed list `[1]…[N]`.
2. Write `<report_dir>/sources.json` as:
   ```json
   {
     "sources": [
       { "n": 1, "adapter": "...", "type": "...", "url": "...", "title": "...",
         "meta": {...}, "fetched_at": "<ISO>" },
       ...
     ],
     "intent": { ... },
     "input": "<target>",
     "input_type": "<type>",
     "created": "<ISO>"
   }
   ```

   **Required NEW fields** (research-engine v0.13+):

   - `content_sha256`: After writing `<report_dir>/README.md` in step 3, compute its sha256 with `sha256sum <report_dir>/README.md | awk '{print $1}'` and patch it into `sources.json`. Order: write README.md → hash it → patch sources.json. README.md is the *content fingerprint authority*.
   - `created_by`: Array of actors. For each adapter that contributed (Stage 4 dispatch), add `{actor_type: "adapter", id: "<adapter-name>", model: "<model-id-or-unknown>", ts: "<adapter-completion-ISO8601>"}`. Order: list adapters in the order they returned.

   After step 7 (Notion push) prepends the `> 📒 Notion:` line to README.md, **recompute the sha256 and patch `sources.json.content_sha256`** so it always matches README.md byte-for-byte.

3. Write `<report_dir>/README.md` using the templates in `lib/report_sections.md`. Merge findings by topic, not by adapter. Dedupe near-duplicate findings. Preserve `[n]` markers.

   **Dedupe is input-type-aware:**
   - For `arxiv` / `huggingface` (academic) inputs: `상세 분석` (§4) MUST be sub-divided into `### 방법론 / 핵심 메커니즘`, `### 실험 결과 / 벤치마크`, `### 저자 한계 / 미해결` — at least 2 fine-grained findings per sub-heading. Do NOT collapse method details, ablations, zero-shot evaluations, or related-work taxonomy into single bullets even when they share a parent topic. The granularity IS the depth signal for academic content.
   - For `youtube` / `blog` / `community`: standard merge-by-topic dedup.
   - For `github` / `context7` (code/docs): keep separate sub-headings for code structure, activity signals, and usage patterns when each has 2+ findings.
4. YouTube only: write `<report_dir>/transcript.md` from the youtube-adapter `artifacts.transcript_md`.
5. For each unique `related[]` entry, write `<report_dir>/related/<kind>-<slug>.md` with a one-paragraph summary + URL. Deduplicate by URL.
6. If any adapter had non-empty `failures[]`, include the `## 수집 실패 (Failures)` section in README.md.
7. **Push to Notion (mirror)** — if `NOTION_TOKEN` + `NOTION_PARENT_PAGE_ID` are set (env or `~/.config/research-engine/notion.env`), run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/push_to_notion.sh" "<report_dir>"`. The script ensures a `research-engine` database exists under the parent page and upserts a **single row per session** (matched by `Slug`). The row's properties capture metadata (Title / Slug / Input URL / Input Type / Created / Purpose / Audience / Sources); the row's page body is a single consolidated report — `README.md` at the top, then one toggle each for Transcript / Followups / Related materials. Capture the returned Notion URL and add it to `sources.json` at `output_notion_url`. Prepend a `> 📒 Notion: <url>` line under the frontmatter of local `README.md`. If the env is not configured, skip silently (log one line).

**Step 7.5 — Update dream-ledger + suggestion check**

After step 7 (Notion push), call reindex once so the new session is reflected:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/memory_reindex.sh"
```

This rebuilds `research/_index/manifest.json` and refreshes `dream-ledger.json` (`sessions_since_last_dream` is recomputed from manifest vs `last_dream_at`).

Then check whether to suggest `/dream`:

```bash
node "${CLAUDE_PLUGIN_ROOT}/lib/memory/ledger.mjs" --suggest? \
  --ledger "research/_index/dream-ledger.json"
# exit 0 + {"should":true,"count":N}  → 제안 줄을 step 8 final message에 포함
# exit 1 + {"should":false,...}        → 제안 생략
```

If suggest = true, the `--suggest?` CLI also writes `suggestion_shown_at` back to the ledger automatically (so the same threshold isn't nagged repeatedly until the next threshold is crossed). Include exactly this line in step 8's final message:

> 💡 dream-ledger: 마지막 dream 이후 {N}개 세션이 누적되었습니다. `/dream` 으로 패턴 인사이트를 추출할 수 있어요.

**Step 7.6 — Auto-ingest into the LLM Wiki**

Fold this session into the durable LLM wiki immediately, so a research run never lives only as a raw `research/<slug>/` artifact. This runs **automatically** at the end of every `/research`; it is a silent no-op when no wiki vault is configured, and can be disabled with `WIKI_AUTO_INGEST=0`.

1. Resolve + (idempotently) bootstrap the wiki vault:
   ```bash
   [ "${WIKI_AUTO_INGEST:-1}" = "0" ] && { echo "wiki auto-ingest disabled (WIKI_AUTO_INGEST=0)"; }
   node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/vault_resolve.mjs" --explain   # inspect "ok"
   VAULT="$(node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/vault_resolve.mjs")"
   ```
   - If `WIKI_AUTO_INGEST=0`, **skip this whole step** (log one line).
   - If the `--explain` JSON shows `"ok": false` (no vault resolved — neither `WIKI_VAULT` nor a registered `LLM_OBSIDIAN_VAULT_NAME`), **skip silently** (log: `wiki auto-ingest skipped — no vault`). Never fail the research run because of the wiki step.
   - Otherwise bootstrap:
     ```bash
     mkdir -p "${VAULT}/concepts" "${VAULT}/entities" "${VAULT}/synthesis" "${VAULT}/ephemeral" "${VAULT}/_drafts" "${VAULT}/_todos" "${VAULT}/_index"
     [ -f "${VAULT}/AGENTS.md" ] || cp "${CLAUDE_PLUGIN_ROOT}/lib/wiki/AGENTS.template.md" "${VAULT}/AGENTS.md"
     [ -f "${VAULT}/index.md" ] || printf '# Wiki Index\n' > "${VAULT}/index.md"
     ```
2. Ingest **this session's `<slug>`** by following `commands/wiki.md` → **Action: ingest → "단일 slug 절차"** exactly (read `research/<slug>/README.md` + `sources.json` + `${VAULT}/index.md` + `${VAULT}/AGENTS.md`; extract entities/concepts per the constitution into a single `${VAULT}/_index/plan-<slug>.json`; then single deterministic apply):
   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/apply.mjs" --vault "${VAULT}" --plan "${VAULT}/_index/plan-<slug>.json" --date <today>
   ```
   - The `log.md` exact-match dedup guard from wiki.md applies, so re-running `/research` for the same slug is a no-op (no duplicate pages).
3. **Mirror the verbatim report** — "결과물 그대로" 요구. distilled 위키와 **별개로** README 전문을 vault `reports/` 에 한국어 파일명으로 보존한다. `WIKI_MIRROR_REPORT`(기본 on)로 끄며, vault 미해석(`ok:false`) 시 함께 skip.
   ```bash
   [ "${WIKI_MIRROR_REPORT:-1}" = "0" ] && echo "wiki report mirror disabled (WIKI_MIRROR_REPORT=0)" || \
   node "${CLAUDE_PLUGIN_ROOT}/lib/wiki/report_mirror.mjs" --vault "${VAULT}" --research-dir "research/<slug>" --date <today>
   ```
   - 결과: `${VAULT}/reports/<date> <한국어 title>.md` — body 는 README 그대로, frontmatter 만 증강(`tags: [ai-generated, research-report]`, `report_slug`, `source`). `report_slug` 기준 idempotent. `reports/` 는 `listPages`/`lint` 스캔 밖이라 concept/entity index·graph 를 오염시키지 않는다.
4. Capture the apply result (created/merged counts) and the mirror result (file path, if any) for the final message. On any error in this step, log it and continue — the research artifacts are already persisted.

8. Final message to user: one line with `<report_dir>/README.md` path + Notion URL (if pushed) + a 2-line TL;DR preview. If Step 7.6 ran, append one line: `📚 LLM Wiki: {created}개 생성 / {merged}개 병합 → {VAULT}` (or `wiki: skipped` when no vault). If the verbatim mirror ran, append one more line: `📄 Report (verbatim): {VAULT}/reports/<file>`.

## Cache policy

- Preview JSON is written under `<report_dir>/cache/preview-<cache_key>.json`.
- Each adapter receives `cache_dir = <report_dir>/cache/` in its inputs. Adapters MAY write `adapter-<name>-<cache_key>.json` for reuse.
- `--fresh` → ignore all cache for this run but still write fresh cache files.

## Failure policy

- Never abort the pipeline because a single adapter failed.
- If ALL adapters fail, still produce a skeleton report with preview content and a prominent Failures section.
- Missing `yt-dlp` on a youtube input → stop before Stage 2 with a clear error telling the user how to install.
