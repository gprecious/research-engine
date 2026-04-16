# research-engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code plugin `research-engine` that turns a URL (YouTube / arXiv / GitHub / blog / docs) or topic keyword into a structured markdown research report with full source attribution, using parallel subagent fanout across source adapters.

**Architecture:** Claude Code plugin installed at `~/.claude/plugins/research-engine/`. Two slash commands (`/research`, `/research-followup`) delegate to a 5-stage orchestrator (Classify → Preview → Intent Q&A → Parallel Dispatch → Synthesize). Seven source adapters live as Claude Code subagents (`agents/*.md`) and are dispatched via the built-in `Agent` tool using `superpowers:dispatching-parallel-agents` semantics. Bash utilities (`scripts/*.sh`) handle deterministic work: URL classification, slugify, cache keys, `yt-dlp` invocation.

**Tech Stack:**
- Claude Code plugin format (`.claude-plugin/plugin.json`, `commands/`, `agents/`, `scripts/`, `lib/`)
- Bash 5 (+ `jq`, `shasum`, `yt-dlp`, `gh`) for deterministic utilities
- `bats-core` for shell script unit tests
- Claude Code built-ins: `Agent`, `Bash`, `Read`, `Write`, `Edit`, `Grep`, `Glob`, `WebFetch`, `WebSearch`
- MCP / plugin integrations: `firecrawl`, `context7`, `huggingface-skills`

**Spec:** `docs/superpowers/specs/2026-04-16-research-engine-design.md`

---

## File Structure (locked before task decomposition)

Project layout — the plugin itself is the deliverable:

```
research-engine/
  .claude-plugin/
    plugin.json                    # plugin manifest
  commands/
    research.md                    # /research slash command
    research-followup.md           # /research-followup slash command
  agents/
    youtube-adapter.md             # tier-1: YouTube captions + metadata
    arxiv-adapter.md               # tier-1: paper summary + related
    github-adapter.md              # tier-1: repo README + issues
    blog-adapter.md                # tier-1: generic blog / docs page
    context7-adapter.md            # tier-1: library docs via context7 MCP
    huggingface-adapter.md         # tier-2: HF model/dataset cards
    community-adapter.md           # tier-2: HN/Reddit/Lobsters threads
  scripts/
    classify_url.sh                # URL → source type string
    slugify.sh                     # title → filesystem-safe slug
    cache_key.sh                   # URL → SHA-1 cache key
    yt_fetch.sh                    # yt-dlp wrapper (preview + full modes)
    find_latest_session.sh         # research/ → latest slug by mtime
  lib/
    adapter_contract.md            # JSON schema adapters MUST return
    report_sections.md             # markdown report section templates
    intent_questions_fallback.md   # fixed 3 Qs used when preview fails
  tests/
    bats/
      test_classify_url.bats
      test_slugify.bats
      test_cache_key.bats
      test_yt_fetch.bats
      test_find_latest_session.bats
    fixtures/
      urls.txt                     # sample URLs per type
      yt_dlp_sample_dump.json      # yt-dlp --dump-json golden output
    acceptance/
      youtube_url.md               # manual acceptance checklist
      arxiv_url.md
      github_url.md
      topic_input.md
      followup_session.md
  install.sh                       # symlinks plugin to ~/.claude/plugins/
  README.md                        # user docs
  DEVELOPMENT.md                   # contributor docs
```

**Boundary decisions:**
- Each **adapter** is a single self-contained file with one clear responsibility — fetch one source type, return the JSON contract. Adapters never read each other; all merging happens in `/research`.
- Each **bash util** is one function, one concern, independently testable via bats.
- **Orchestration logic** lives in `commands/research.md` (slash command prompt); it is the only place that dispatches adapters and synthesizes.
- **Templates** (`lib/*.md`) are reference material read by `commands/research.md`; they are NEVER executed directly.

---

## Phase 0 — Scaffolding

### Task 1: Initialize plugin skeleton

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `README.md`
- Create: `DEVELOPMENT.md`
- Modify: `.gitignore`

- [ ] **Step 1: Write plugin manifest**

Create `.claude-plugin/plugin.json`:

```json
{
  "name": "research-engine",
  "version": "0.1.0",
  "description": "Deep research engine for URLs (YouTube, arXiv, GitHub, blogs) or topic keywords. Produces structured markdown reports with full source attribution via parallel subagent fanout.",
  "author": {
    "name": "gprecious",
    "email": "yprecious@gmail.com"
  }
}
```

- [ ] **Step 2: Write user-facing README**

Create `README.md`:

````markdown
# research-engine

Deep research via Claude Code slash commands. Give it a URL or a topic — it returns a structured markdown report with citations.

## Installation

```bash
./install.sh            # symlinks to ~/.claude/plugins/research-engine
```

Then restart Claude Code or run `/plugins reload`.

## Usage

```
/research https://youtu.be/xxxxx          # analyze a YouTube video
/research https://arxiv.org/abs/2301.xxxx # analyze a paper
/research "MoE LLM trends in 2026"        # topic research
/research https://... --yes               # skip intent Q&A
/research https://... --fresh             # bypass cache

/research-followup "저자 배경 더"         # ask follow-up on latest session
/research-followup "..." --slug <name>    # target specific session
```

Output lands in `research/YYYY-MM-DD-<slug>/README.md`.

## Requirements

- `yt-dlp` in `PATH` (YouTube captions)
- `gh` CLI authenticated (GitHub)
- `jq` (JSON munging)
- Claude Code plugins: `firecrawl`, `context7`, `huggingface-skills`

## Docs

- User guide: this file
- Design spec: `docs/superpowers/specs/2026-04-16-research-engine-design.md`
- Contributor guide: `DEVELOPMENT.md`
````

- [ ] **Step 3: Write DEVELOPMENT.md**

Create `DEVELOPMENT.md`:

````markdown
# Development

## Layout

See `docs/superpowers/plans/2026-04-16-research-engine.md` for the full file map and task breakdown.

## Running shell tests

```bash
sudo apt install -y bats   # one-time
bats tests/bats/
```

## Manual acceptance

See `tests/acceptance/*.md` — each file is a checklist you step through in a fresh Claude Code session with the plugin installed.

## Adapter contract

All adapters return the JSON specified in `lib/adapter_contract.md`. The orchestrator (`commands/research.md`) merges these into the report.
````

- [ ] **Step 4: Extend .gitignore**

Replace the current `research/*/cache/` and `research/*/transcript.md` lines with a full ignore — acceptance runs inside this repo will create `research/` content we don't want tracked. Also add `install.log`.

Resulting `.gitignore`:

```
# superpowers brainstorm session files
.superpowers/

# research outputs (acceptance runs and real usage both land here)
research/

# plugin install symlink artifacts
install.log

# Node / Python / editors
node_modules/
__pycache__/
*.pyc
.venv/
venv/
.DS_Store
.idea/
.vscode/
```

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json README.md DEVELOPMENT.md .gitignore
git commit -m "chore: scaffold research-engine plugin manifest and docs"
```

---

### Task 2: Install-script and bats fixture

**Files:**
- Create: `install.sh`
- Create: `tests/fixtures/urls.txt`

- [ ] **Step 1: Write install.sh**

Create `install.sh`:

```bash
#!/usr/bin/env bash
# Symlinks this plugin directory into ~/.claude/plugins/research-engine so
# Claude Code can discover it. Re-run safely; it removes any existing symlink.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.claude/plugins/research-engine"

mkdir -p "$HOME/.claude/plugins"

if [[ -L "$TARGET" ]]; then
  rm "$TARGET"
elif [[ -e "$TARGET" ]]; then
  echo "ERROR: $TARGET exists and is not a symlink. Remove it first." >&2
  exit 1
fi

ln -s "$PLUGIN_DIR" "$TARGET"
echo "Linked: $TARGET -> $PLUGIN_DIR"
echo "Restart Claude Code or run /plugins reload."
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x install.sh`

- [ ] **Step 3: Write URL fixtures**

Create `tests/fixtures/urls.txt`:

```
https://www.youtube.com/watch?v=dQw4w9WgXcQ	youtube
https://youtu.be/dQw4w9WgXcQ	youtube
https://youtube.com/shorts/abc123	youtube
https://arxiv.org/abs/2301.12345	arxiv
https://arxiv.org/pdf/2301.12345.pdf	arxiv
https://arxiv.org/abs/2301.12345v2	arxiv
https://github.com/anthropics/claude-code	github
https://github.com/anthropics/claude-code/issues/100	github
https://github.com/anthropics/claude-code/pull/200	github
https://huggingface.co/meta-llama/Llama-3-8B	huggingface
https://huggingface.co/datasets/squad	huggingface
https://news.ycombinator.com/item?id=39000000	community
https://www.reddit.com/r/LocalLLaMA/comments/abc/xyz/	community
https://lobste.rs/s/abcde/some_story	community
https://engineering.example.com/posts/some-post	blog
https://blog.example.io/some-post	blog
best practices for RAG pipelines	topic
MoE LLM trends 2026	topic
```

Format: `<url-or-text><TAB><expected-type>`.

- [ ] **Step 4: Commit**

```bash
git add install.sh tests/fixtures/urls.txt
git commit -m "chore: add install script and URL classification fixtures"
```

---

## Phase 1 — Deterministic bash utilities (TDD with bats)

### Task 3: `classify_url.sh` — URL → source type

**Files:**
- Create: `scripts/classify_url.sh`
- Create: `tests/bats/test_classify_url.bats`

- [ ] **Step 1: Write failing bats test**

Create `tests/bats/test_classify_url.bats`:

```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/classify_url.sh"

@test "youtube watch URL" {
  run "$SCRIPT" "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  [ "$status" -eq 0 ]
  [ "$output" = "youtube" ]
}

@test "youtu.be short URL" {
  run "$SCRIPT" "https://youtu.be/dQw4w9WgXcQ"
  [ "$status" -eq 0 ]
  [ "$output" = "youtube" ]
}

@test "arxiv abs URL" {
  run "$SCRIPT" "https://arxiv.org/abs/2301.12345"
  [ "$status" -eq 0 ]
  [ "$output" = "arxiv" ]
}

@test "arxiv pdf URL" {
  run "$SCRIPT" "https://arxiv.org/pdf/2301.12345.pdf"
  [ "$status" -eq 0 ]
  [ "$output" = "arxiv" ]
}

@test "github repo URL" {
  run "$SCRIPT" "https://github.com/anthropics/claude-code"
  [ "$status" -eq 0 ]
  [ "$output" = "github" ]
}

@test "huggingface model URL" {
  run "$SCRIPT" "https://huggingface.co/meta-llama/Llama-3-8B"
  [ "$status" -eq 0 ]
  [ "$output" = "huggingface" ]
}

@test "HN community URL" {
  run "$SCRIPT" "https://news.ycombinator.com/item?id=39000000"
  [ "$status" -eq 0 ]
  [ "$output" = "community" ]
}

@test "reddit community URL" {
  run "$SCRIPT" "https://www.reddit.com/r/LocalLLaMA/comments/abc/xyz/"
  [ "$status" -eq 0 ]
  [ "$output" = "community" ]
}

@test "generic blog URL falls back to blog" {
  run "$SCRIPT" "https://engineering.example.com/posts/some-post"
  [ "$status" -eq 0 ]
  [ "$output" = "blog" ]
}

@test "non-URL string classifies as topic" {
  run "$SCRIPT" "best practices for RAG pipelines"
  [ "$status" -eq 0 ]
  [ "$output" = "topic" ]
}

@test "empty input is an error" {
  run "$SCRIPT" ""
  [ "$status" -ne 0 ]
}

@test "missing argument is an error" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test, expect ALL to fail**

Run: `bats tests/bats/test_classify_url.bats`
Expected: all tests fail — script does not exist yet.

- [ ] **Step 3: Write classify_url.sh**

Create `scripts/classify_url.sh`:

```bash
#!/usr/bin/env bash
# Classify the argument as one of:
#   youtube | arxiv | github | huggingface | community | blog | topic
# Usage: classify_url.sh <input>
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: classify_url.sh <url-or-text>" >&2
  exit 2
fi

input="$1"

# Non-URL → topic
if [[ "$input" != http://* && "$input" != https://* ]]; then
  echo "topic"
  exit 0
fi

case "$input" in
  *youtube.com/*|*youtu.be/*)                       echo "youtube" ;;
  *arxiv.org/*)                                     echo "arxiv" ;;
  *github.com/*)                                    echo "github" ;;
  *huggingface.co/*)                                echo "huggingface" ;;
  *news.ycombinator.com/*|*reddit.com/*|*lobste.rs/*) echo "community" ;;
  *)                                                echo "blog" ;;
esac
```

- [ ] **Step 4: Make executable and re-run tests**

```bash
chmod +x scripts/classify_url.sh
bats tests/bats/test_classify_url.bats
```

Expected: all 12 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/classify_url.sh tests/bats/test_classify_url.bats
git commit -m "feat(scripts): classify_url.sh with bats coverage"
```

---

### Task 4: `slugify.sh` — title → filesystem slug

**Files:**
- Create: `scripts/slugify.sh`
- Create: `tests/bats/test_slugify.bats`

- [ ] **Step 1: Write failing bats test**

Create `tests/bats/test_slugify.bats`:

```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/slugify.sh"

@test "ASCII title" {
  run "$SCRIPT" "Attention Is All You Need"
  [ "$status" -eq 0 ]
  [ "$output" = "attention-is-all-you-need" ]
}

@test "strips punctuation" {
  run "$SCRIPT" "GPT-4, Explained!"
  [ "$status" -eq 0 ]
  [ "$output" = "gpt-4-explained" ]
}

@test "collapses whitespace" {
  run "$SCRIPT" "Multi   Space    Title"
  [ "$status" -eq 0 ]
  [ "$output" = "multi-space-title" ]
}

@test "keeps hangul as-is when present" {
  run "$SCRIPT" "전문가 혼합 구조 설명"
  [ "$status" -eq 0 ]
  [ "$output" = "전문가-혼합-구조-설명" ]
}

@test "truncates to 40 chars boundary" {
  run "$SCRIPT" "this is a very long title that absolutely must be truncated at the boundary"
  [ "$status" -eq 0 ]
  # 40 chars max, no trailing hyphen
  [ "${#output}" -le 40 ]
  [[ "$output" != *-  ]]
}

@test "empty input errors" {
  run "$SCRIPT" ""
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run tests, expect failure**

Run: `bats tests/bats/test_slugify.bats`
Expected: all fail.

- [ ] **Step 3: Write slugify.sh**

Create `scripts/slugify.sh`:

```bash
#!/usr/bin/env bash
# Lowercase, hyphenate whitespace, drop punctuation, cap at 40 chars.
# Preserves non-ASCII letters (e.g. Hangul) so Korean titles are readable.
# Usage: slugify.sh <text>
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: slugify.sh <text>" >&2
  exit 2
fi

LC_ALL=C.UTF-8 printf '%s' "$1" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^[:alnum:][:space:]가-힣ぁ-んァ-ヶ一-龥-]//g' \
  | sed -E 's/[[:space:]_]+/-/g' \
  | sed -E 's/-+/-/g' \
  | sed -E 's/^-|-$//g' \
  | cut -c 1-40 \
  | sed -E 's/-+$//'
```

- [ ] **Step 4: Run tests, expect pass**

```bash
chmod +x scripts/slugify.sh
bats tests/bats/test_slugify.bats
```

Expected: all 6 pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/slugify.sh tests/bats/test_slugify.bats
git commit -m "feat(scripts): slugify.sh with bats coverage"
```

---

### Task 5: `cache_key.sh` — URL → SHA-1 prefix

**Files:**
- Create: `scripts/cache_key.sh`
- Create: `tests/bats/test_cache_key.bats`

- [ ] **Step 1: Write failing test**

Create `tests/bats/test_cache_key.bats`:

```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/cache_key.sh"

@test "returns 12-char hex for URL" {
  run "$SCRIPT" "https://youtu.be/dQw4w9WgXcQ"
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 12 ]
  [[ "$output" =~ ^[0-9a-f]+$ ]]
}

@test "same URL yields same key" {
  out1=$("$SCRIPT" "https://example.com/foo")
  out2=$("$SCRIPT" "https://example.com/foo")
  [ "$out1" = "$out2" ]
}

@test "different URLs yield different keys" {
  out1=$("$SCRIPT" "https://example.com/foo")
  out2=$("$SCRIPT" "https://example.com/bar")
  [ "$out1" != "$out2" ]
}

@test "empty input errors" {
  run "$SCRIPT" ""
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run, expect failure**

Run: `bats tests/bats/test_cache_key.bats`
Expected: fail.

- [ ] **Step 3: Write cache_key.sh**

Create `scripts/cache_key.sh`:

```bash
#!/usr/bin/env bash
# SHA-1 of the input, first 12 hex chars. Stable cache key for a URL.
# Usage: cache_key.sh <url>
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: cache_key.sh <url>" >&2
  exit 2
fi

printf '%s' "$1" | shasum -a 1 | cut -c1-12
```

- [ ] **Step 4: Run, expect pass**

```bash
chmod +x scripts/cache_key.sh
bats tests/bats/test_cache_key.bats
```

Expected: all 4 pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/cache_key.sh tests/bats/test_cache_key.bats
git commit -m "feat(scripts): cache_key.sh with bats coverage"
```

---

### Task 6: `yt_fetch.sh` — yt-dlp wrapper (preview + full)

**Files:**
- Create: `scripts/yt_fetch.sh`
- Create: `tests/bats/test_yt_fetch.bats`
- Create: `tests/fixtures/yt_dlp_sample_dump.json`

- [ ] **Step 1: Create fixture**

Create `tests/fixtures/yt_dlp_sample_dump.json`:

```json
{
  "id": "dQw4w9WgXcQ",
  "title": "Sample Video Title",
  "description": "Sample description line 1.\nSample description line 2.",
  "uploader": "Sample Channel",
  "duration": 212,
  "language": "en",
  "chapters": [
    {"title": "Intro", "start_time": 0, "end_time": 30},
    {"title": "Main content", "start_time": 30, "end_time": 180},
    {"title": "Outro", "start_time": 180, "end_time": 212}
  ],
  "subtitles": {"en": [{"ext": "vtt"}]},
  "automatic_captions": {"ko": [{"ext": "vtt"}], "en": [{"ext": "vtt"}]}
}
```

- [ ] **Step 2: Write failing bats test**

Create `tests/bats/test_yt_fetch.bats`:

```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/yt_fetch.sh"
FIXTURE="$BATS_TEST_DIRNAME/../fixtures/yt_dlp_sample_dump.json"

setup() {
  TMPDIR_TEST="$(mktemp -d)"
}
teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "metadata subcommand with fixture yields JSON with id and title" {
  # --from-fixture reads the local JSON instead of calling yt-dlp
  run "$SCRIPT" metadata --from-fixture "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id == "dQw4w9WgXcQ"' > /dev/null
  echo "$output" | jq -e '.title == "Sample Video Title"' > /dev/null
}

@test "metadata subcommand picks caption language: original (en) first" {
  run "$SCRIPT" metadata --from-fixture "$FIXTURE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.selected_caption_lang == "en"' > /dev/null
}

@test "metadata subcommand falls back to ko when original lang missing" {
  # override language to unsupported value
  local modified
  modified=$(jq '.language = "xx" | del(.subtitles)' "$FIXTURE")
  echo "$modified" > "$TMPDIR_TEST/modified.json"
  run "$SCRIPT" metadata --from-fixture "$TMPDIR_TEST/modified.json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.selected_caption_lang == "ko"' > /dev/null
}

@test "missing subcommand errors" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "unknown subcommand errors" {
  run "$SCRIPT" nonsense
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 3: Run test, expect failure**

Run: `bats tests/bats/test_yt_fetch.bats`
Expected: fail.

- [ ] **Step 4: Write yt_fetch.sh**

Create `scripts/yt_fetch.sh`:

```bash
#!/usr/bin/env bash
# Wrapper over yt-dlp for the research-engine preview/full pipelines.
#
# Subcommands:
#   metadata <URL>                       — prints JSON with selected caption lang
#   metadata --from-fixture <PATH>       — same, but reads a local JSON dump (for tests)
#   captions <URL> <DIR>                 — downloads captions into DIR as <id>.<lang>.vtt
#
# Output JSON schema for `metadata`:
# {
#   "id": "...", "title": "...", "description": "...", "uploader": "...",
#   "duration": <seconds>, "language": "<orig>",
#   "chapters": [...], "selected_caption_lang": "<code>",
#   "caption_langs_available": ["ko","en", ...]
# }
#
# Caption language priority: video original language → ko → en → first available.
set -euo pipefail

die() { echo "yt_fetch: $*" >&2; exit 2; }

pick_caption_lang() {
  # $1 = raw JSON dump
  jq -r '
    (.language // "") as $orig
    | ((.subtitles // {}) | keys) as $subs
    | ((.automatic_captions // {}) | keys) as $auto
    | ($subs + $auto | unique) as $all
    | if ($all | length) == 0 then ""
      elif ($all | index($orig)) then $orig
      elif ($all | index("ko")) then "ko"
      elif ($all | index("en")) then "en"
      else $all[0]
      end
  '
}

list_caption_langs() {
  jq -c '
    (((.subtitles // {}) | keys) + ((.automatic_captions // {}) | keys)) | unique
  '
}

case "${1:-}" in
  metadata)
    shift
    if [[ "${1:-}" == "--from-fixture" ]]; then
      shift
      [[ -f "${1:-}" ]] || die "fixture not found: ${1:-}"
      raw="$(cat "$1")"
    else
      [[ -n "${1:-}" ]] || die "metadata needs <URL> or --from-fixture <PATH>"
      raw="$(yt-dlp --skip-download --write-auto-sub --write-sub --dump-json "$1")"
    fi
    lang="$(printf '%s' "$raw" | pick_caption_lang)"
    langs="$(printf '%s' "$raw" | list_caption_langs)"
    printf '%s' "$raw" | jq \
      --arg lang "$lang" \
      --argjson langs "$langs" \
      '. + {selected_caption_lang: $lang, caption_langs_available: $langs}'
    ;;

  captions)
    [[ $# -eq 3 ]] || die "captions needs <URL> <DIR>"
    url="$2"; dir="$3"
    mkdir -p "$dir"
    # Download all available subs and auto-captions (orchestrator will pick).
    yt-dlp \
      --skip-download \
      --write-auto-sub \
      --write-sub \
      --sub-format "vtt" \
      --convert-subs "vtt" \
      -o "$dir/%(id)s.%(ext)s" \
      "$url"
    ;;

  ""|-h|--help)
    sed -n '2,10p' "$0"
    exit 1
    ;;

  *)
    die "unknown subcommand: $1"
    ;;
esac
```

- [ ] **Step 5: Run tests, expect pass**

```bash
chmod +x scripts/yt_fetch.sh
bats tests/bats/test_yt_fetch.bats
```

Expected: all 5 pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/yt_fetch.sh tests/bats/test_yt_fetch.bats tests/fixtures/yt_dlp_sample_dump.json
git commit -m "feat(scripts): yt_fetch.sh wrapper with fixture-driven tests"
```

---

### Task 7: `find_latest_session.sh`

**Files:**
- Create: `scripts/find_latest_session.sh`
- Create: `tests/bats/test_find_latest_session.bats`

- [ ] **Step 1: Write failing test**

Create `tests/bats/test_find_latest_session.bats`:

```bash
#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/find_latest_session.sh"

setup() {
  TMPROOT="$(mktemp -d)"
  mkdir -p "$TMPROOT/research/2026-04-10-alpha"
  mkdir -p "$TMPROOT/research/2026-04-12-beta"
  mkdir -p "$TMPROOT/research/2026-04-14-gamma"
  # Make "beta" the newest by touching it last
  touch "$TMPROOT/research/2026-04-10-alpha"
  sleep 0.05
  touch "$TMPROOT/research/2026-04-14-gamma"
  sleep 0.05
  touch "$TMPROOT/research/2026-04-12-beta"
}
teardown() { rm -rf "$TMPROOT"; }

@test "returns slug of most recently touched session" {
  run "$SCRIPT" "$TMPROOT/research"
  [ "$status" -eq 0 ]
  [ "$output" = "2026-04-12-beta" ]
}

@test "errors when research dir missing" {
  run "$SCRIPT" "$TMPROOT/nonexistent"
  [ "$status" -ne 0 ]
}

@test "errors when research dir empty" {
  local empty
  empty="$(mktemp -d)"
  run "$SCRIPT" "$empty"
  [ "$status" -ne 0 ]
  rmdir "$empty"
}
```

- [ ] **Step 2: Run, expect failure**

Run: `bats tests/bats/test_find_latest_session.bats`

- [ ] **Step 3: Write script**

Create `scripts/find_latest_session.sh`:

```bash
#!/usr/bin/env bash
# Print slug of the most recently modified session folder under <research_dir>.
# Exit 1 if directory is missing or empty.
# Usage: find_latest_session.sh <research_dir>
set -euo pipefail

root="${1:-}"
[[ -d "$root" ]] || { echo "find_latest_session: no such dir: $root" >&2; exit 1; }

latest="$(find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %f\n' 2>/dev/null \
  | sort -rn | head -n1 | cut -d' ' -f2-)"

[[ -n "$latest" ]] || { echo "find_latest_session: no sessions under $root" >&2; exit 1; }
echo "$latest"
```

- [ ] **Step 4: Run, expect pass**

```bash
chmod +x scripts/find_latest_session.sh
bats tests/bats/test_find_latest_session.bats
```

- [ ] **Step 5: Commit**

```bash
git add scripts/find_latest_session.sh tests/bats/test_find_latest_session.bats
git commit -m "feat(scripts): find_latest_session.sh for followup slug resolution"
```

---

## Phase 2 — Shared library (contracts and templates)

### Task 8: Adapter JSON contract

**Files:**
- Create: `lib/adapter_contract.md`

- [ ] **Step 1: Write contract doc**

Create `lib/adapter_contract.md`:

````markdown
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
````

- [ ] **Step 2: Commit**

```bash
git add lib/adapter_contract.md
git commit -m "docs(lib): adapter JSON contract"
```

---

### Task 9: Report section templates

**Files:**
- Create: `lib/report_sections.md`

- [ ] **Step 1: Write templates**

Create `lib/report_sections.md`:

````markdown
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

## §7. 수집 실패 (Failures) — include only if non-empty

```markdown
## 수집 실패 (Failures)

- `{{adapter}}` / `{{step}}` — {{error_summary}}
```

## §8. Sources

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
````

- [ ] **Step 2: Commit**

```bash
git add lib/report_sections.md
git commit -m "docs(lib): report section templates"
```

---

### Task 10: Intent-questions fallback

**Files:**
- Create: `lib/intent_questions_fallback.md`

- [ ] **Step 1: Write fallback**

Create `lib/intent_questions_fallback.md`:

````markdown
# Intent Questions Fallback

Used when preview (Stage 2) fails and dynamic questions can't be generated.

Ask these 3 fixed questions:

1. **왜 이 자료를 분석하시나요?**
   - (a) 학습 / 이해
   - (b) 업무 적용 / 의사결정
   - (c) 공유용 요약
   - (d) 기타 (자유 서술)

2. **어떤 관점에 가장 집중해드릴까요?**
   - (a) 개념 · 이론
   - (b) 실행 · 구현 세부
   - (c) 장단점 · 트레이드오프
   - (d) 기타 (자유 서술)

3. **귀하의 배경지식 수준은?**
   - (a) 입문 — 용어부터 풀어 설명 필요
   - (b) 중급 — 요점 중심, 배경은 짧게
   - (c) 전문가 — 전문 용어 그대로, 새로움에 집중
````

- [ ] **Step 2: Commit**

```bash
git add lib/intent_questions_fallback.md
git commit -m "docs(lib): intent-question fallback set"
```

---

## Phase 3 — Tier-1 source adapters

Each adapter is a Claude Code subagent. The orchestrator dispatches it via the `Agent` tool with a focused prompt (Intent summary + specific work order).

> **Shared style notes for all adapter files:**
> - YAML frontmatter: `name`, `description`, optional `model`.
> - Body prompt is concise: role, inputs, tools to use, OUTPUT CONTRACT pointer to `lib/adapter_contract.md`, and a "respond with a single fenced JSON block" reminder.

### Task 11: `youtube-adapter`

**Files:**
- Create: `agents/youtube-adapter.md`

- [ ] **Step 1: Write adapter**

Create `agents/youtube-adapter.md`:

````markdown
---
name: youtube-adapter
description: Extract YouTube captions, chapters, and metadata. Emit findings with timecodes. Return JSON per adapter contract.
model: sonnet
---

You are the **youtube-adapter** for research-engine. Your job is to fully analyze a single YouTube video and return a JSON response per `lib/adapter_contract.md`.

## Inputs (provided in the dispatch prompt)

- `url`: the YouTube URL
- `cache_dir`: path for caching raw downloads (`research/<slug>/cache/yt-dlp-<id>/`)
- `intent`: object with `purpose`, `focus`, `audience_level`
- `slug`: session slug
- `fresh`: bool — if true, bypass cache

## Steps

1. **Metadata** — run `scripts/yt_fetch.sh metadata "$url"` and parse. If `selected_caption_lang == ""`, still proceed but note the failure.

2. **Captions** — if `fresh` or the cache dir is missing the `<id>.<lang>.vtt`, run `scripts/yt_fetch.sh captions "$url" "$cache_dir"`. Otherwise reuse cached files.

3. **Transcript** — convert the selected-lang VTT to plain text paragraphs grouped by chapter (or by 2-minute windows if no chapters). Write to `{{report_dir}}/transcript.md` with one paragraph per chapter, prefixed by `### {{chapter_title}} ({{start}}–{{end}})`.

4. **Findings** — produce 6–12 findings covering the video's claims/insights. Each finding:
   - `text`: Korean, one fact
   - `source_ids`: `["s1"]` (the single source for this adapter)
   - `timecode`: `mm:ss` tied to the transcript location
   - `quote` (optional): verbatim excerpt in original language when the wording matters

5. **Chapters** — emit `artifacts.chapters[]` with summaries (3–5 sentences each).

6. **Related hints** — scan transcript for paper titles / arXiv IDs / repo URLs / named libraries. Put them in `artifacts.related[]` as `{kind, url?, title}` for the orchestrator to hand off to other adapters.

7. **Intent tailoring** — shape finding selection by `intent.focus` (concepts vs implementation vs tradeoffs) and depth by `intent.audience_level`.

## Output contract

Return one fenced JSON block per `lib/adapter_contract.md`. A short human status line before the block is allowed; nothing after.

## Failure modes

- No captions at all → `status: "failed"`, still produce metadata-only sources + findings from title/description.
- yt-dlp missing → `status: "failed"`, `failures: [{"step":"yt_dlp_missing", "error":"..."}]`.
- Partial caption download → `status: "partial"`, note which chapters are missing.
````

- [ ] **Step 2: Commit**

```bash
git add agents/youtube-adapter.md
git commit -m "feat(agents): youtube-adapter subagent"
```

---

### Task 12: `arxiv-adapter`

**Files:**
- Create: `agents/arxiv-adapter.md`

- [ ] **Step 1: Write adapter**

Create `agents/arxiv-adapter.md`:

````markdown
---
name: arxiv-adapter
description: Analyze an arXiv paper — abstract, contributions, related work — and surface implementation repos. Return JSON per adapter contract.
model: sonnet
---

You are the **arxiv-adapter**. Analyze a single arXiv paper (or URL that resolves to one) and return the JSON contract.

## Inputs

- `url` or `arxiv_id` (one is given)
- `intent`: object
- `cache_dir`
- `fresh`: bool

## Tools

- Prefer the `huggingface-skills:hugging-face-paper-pages` skill for structured metadata (title, abstract, authors, linked models/datasets/spaces, linked GitHub repo).
- Fall back to `firecrawl scrape` on the `/abs/<id>` page.
- Use `WebFetch` on the PDF URL only when needed for deep detail.

## Steps

1. **Resolve ID** — if `url`, extract ID from path `/abs/<id>` or `/pdf/<id>.pdf`.
2. **Metadata** — pull title, abstract, authors, categories, linked repos.
3. **Structured summary (findings)** — 5–10 findings:
   - Problem statement
   - Key contributions (one per finding, ideally)
   - Method summary
   - Evaluation setup + headline numbers
   - Limitations / open questions
4. **Related work** — list 3–7 `related[]` entries (other papers cited for context, plus any official/community implementations found via paper-page links or a single `firecrawl search` for `"<paper title>" github`).
5. **Intent tailoring** — if `intent.purpose` is "의사결정", emphasize strengths vs alternatives and deployment caveats; if "학습", emphasize method and notation.

## Output contract

Single fenced JSON block per `lib/adapter_contract.md`.

## Failure modes

- Cannot resolve arXiv ID → `status: "failed"` with reason.
- Paper page unreachable → `status: "partial"` if at least abstract was obtained via fallback.
````

- [ ] **Step 2: Commit**

```bash
git add agents/arxiv-adapter.md
git commit -m "feat(agents): arxiv-adapter subagent"
```

---

### Task 13: `github-adapter`

**Files:**
- Create: `agents/github-adapter.md`

- [ ] **Step 1: Write adapter**

Create `agents/github-adapter.md`:

````markdown
---
name: github-adapter
description: Analyze a GitHub repo/issue/PR — structure, README, recent activity — and return JSON per adapter contract.
model: sonnet
---

You are the **github-adapter**. Analyze a single GitHub target (repo, issue, or PR) and return the JSON contract.

## Inputs

- `url`
- `intent`
- `cache_dir`
- `fresh`: bool

## Tools

- `gh` CLI for structured repo/issue/PR data (authenticated when available, public API otherwise).
- `firecrawl scrape` for README rendering when needed.
- `Read` on cached file if present.

## Steps

1. **Parse URL** — extract `owner`, `repo`, and optional `issues/<n>` or `pull/<n>`.
2. **Repo metadata** — `gh repo view <owner>/<repo> --json name,description,stargazerCount,forkCount,pushedAt,primaryLanguage,licenseInfo,topics`.
3. **README** — `gh api repos/<owner>/<repo>/readme --jq .content | base64 -d` (truncate at 20k chars).
4. **Issue/PR detail** — if URL was issue/PR: `gh issue view <n>` or `gh pr view <n> --json title,body,state,additions,deletions`.
5. **Findings** — 5–10 findings:
   - What the project does (from README opening)
   - Primary abstractions / entry points
   - Notable design decisions
   - Activity/maturity signals (stars, last push, issue cadence)
   - If issue/PR context: status, substance of discussion
6. **Related hints** — linked repos, papers, homepages mentioned in README → `artifacts.related[]`.
7. **Intent tailoring** — if `intent.purpose == "의사결정"`, emphasize license, activity, alternatives; if "학습", emphasize concept walk-through.

## Output contract

Single fenced JSON block per `lib/adapter_contract.md`.

## Failure modes

- Private / 404 → `status: "failed"`.
- Rate-limited → retry once, then `status: "partial"` with whatever succeeded.
````

- [ ] **Step 2: Commit**

```bash
git add agents/github-adapter.md
git commit -m "feat(agents): github-adapter subagent"
```

---

### Task 14: `blog-adapter`

**Files:**
- Create: `agents/blog-adapter.md`

- [ ] **Step 1: Write adapter**

Create `agents/blog-adapter.md`:

````markdown
---
name: blog-adapter
description: Scrape a single blog / docs page, optionally follow connected posts, and return JSON per adapter contract.
model: sonnet
---

You are the **blog-adapter**. Analyze a single blog or docs page (and 1-hop related posts on the same site) and return the JSON contract.

## Inputs

- `url`
- `intent`
- `cache_dir`
- `fresh`: bool

## Tools

- `firecrawl scrape` (preferred) for single-page markdown.
- `firecrawl crawl` with depth=1 ONLY when the main page is clearly a series/index (TOC-like, lots of in-site links). Cap at 5 pages.
- `WebFetch` as fallback when firecrawl is unavailable.

## Steps

1. **Fetch main page** as markdown.
2. **Extract** — title, author (if obvious), publish date (if obvious), main body.
3. **Findings** — 5–10 claims from the body, each with `source_ids` to the page.
4. **Quotes** — 1–3 verbatim quotes into `findings[].quote` when wording matters.
5. **Related** — same-series next/prev posts, explicitly linked papers/repos → `artifacts.related[]`.
6. **Intent tailoring** — same pattern as other adapters.

## Output contract

Single fenced JSON block per `lib/adapter_contract.md`.

## Failure modes

- Paywall / 403 → `status: "failed"` with step `"fetch"`.
- Sparse content (<300 chars) → `status: "partial"`.
````

- [ ] **Step 2: Commit**

```bash
git add agents/blog-adapter.md
git commit -m "feat(agents): blog-adapter subagent"
```

---

### Task 15: `context7-adapter`

**Files:**
- Create: `agents/context7-adapter.md`

- [ ] **Step 1: Write adapter**

Create `agents/context7-adapter.md`:

````markdown
---
name: context7-adapter
description: Pull current library / framework / SDK documentation via the context7 MCP for libraries referenced in the research session.
model: sonnet
---

You are the **context7-adapter**. Given one or more library names mentioned in the session, retrieve their current official docs via the `context7` MCP.

## Inputs

- `libraries`: string array (e.g. `["React 19", "next.js app router"]`)
- `intent`
- `cache_dir`

## Tools

- `mcp__plugin_context7_context7__resolve-library-id`
- `mcp__plugin_context7_context7__query-docs`

## Steps

1. For each library name, resolve the context7 library id.
2. Query docs with a topic drawn from `intent.focus` (or "overview" when unclear). Cap at 2 queries per library.
3. **Findings** — 2–4 per library, each citing the doc source.
4. **Artifacts** — emit `related[]` with `{kind:"docs", url, title}` pointing at the docs deep-links returned.

## Output contract

Single fenced JSON block per `lib/adapter_contract.md`. If no libraries were provided, return immediately with `status:"ok"` and empty arrays.

## Failure modes

- Context7 MCP unavailable → `status: "failed"` with `step: "mcp_unavailable"`.
- Unknown library → skip that library, record it in `failures[]` but keep the adapter `status: "partial"` if others succeeded.
````

- [ ] **Step 2: Commit**

```bash
git add agents/context7-adapter.md
git commit -m "feat(agents): context7-adapter subagent"
```

---

## Phase 4 — Tier-2 source adapters (best-effort)

### Task 16: `huggingface-adapter`

**Files:**
- Create: `agents/huggingface-adapter.md`

- [ ] **Step 1: Write adapter**

Create `agents/huggingface-adapter.md`:

````markdown
---
name: huggingface-adapter
description: Fetch Hugging Face model / dataset / space card metadata via hf CLI and HF skills. Tier-2; skipped if no HF target detected.
model: sonnet
---

You are the **huggingface-adapter**. Pull HF model/dataset/space card data when the session involves named HF assets.

## Inputs

- `targets`: string array (e.g. `["meta-llama/Llama-3-8B", "datasets/squad"]`)
- `intent`
- `cache_dir`

## Tools

- `huggingface-skills:hf-cli`
- `huggingface-skills:hugging-face-dataset-viewer` (datasets only)

## Steps

1. For each target, run `hf` CLI to fetch card + metadata.
2. Findings: intended use, license, dataset size / model params, evaluation scores if present.
3. `artifacts.related[]` ← linked papers, parent / derived models.
4. If target is empty array → immediate `status:"ok"` with empty arrays.

## Output contract

Single fenced JSON block per `lib/adapter_contract.md`.

## Failure modes

- Target not found → per-target entry in `failures[]`.
- `hf` not authenticated and target is gated → `status: "partial"`, record.
````

- [ ] **Step 2: Commit**

```bash
git add agents/huggingface-adapter.md
git commit -m "feat(agents): huggingface-adapter subagent"
```

---

### Task 17: `community-adapter`

**Files:**
- Create: `agents/community-adapter.md`

- [ ] **Step 1: Write adapter**

Create `agents/community-adapter.md`:

````markdown
---
name: community-adapter
description: Summarize HN / Reddit / Lobsters threads referenced in the session. Tier-2; captures crowd reaction and dissenting views.
model: sonnet
---

You are the **community-adapter**. Analyze one or more community threads and return JSON.

## Inputs

- `thread_urls`: string array
- `topic_query`: optional string (topic mode) — if present and `thread_urls` is empty, do a single WebSearch to find 2–3 top threads first.
- `intent`
- `cache_dir`

## Tools

- `firecrawl scrape` for thread pages
- `WebSearch` for thread discovery in topic mode
- `WebFetch` fallback

## Steps

1. Resolve thread list (from `thread_urls` or WebSearch).
2. For each thread, scrape post + top 20 comments (by score when available).
3. Findings (4–8 total, aggregate across threads):
   - Dominant positive take
   - Dominant critical take
   - Notable dissent / edge-case reports
   - Links mentioned in comments → `related[]`
4. Include 1–3 verbatim quotes when the phrasing is representative.

## Output contract

Single fenced JSON block per `lib/adapter_contract.md`.

## Failure modes

- Thread gone / 403 → skip, record in `failures[]`.
- WebSearch yields nothing relevant → `status: "ok"` with empty findings, note "no community signal".
````

- [ ] **Step 2: Commit**

```bash
git add agents/community-adapter.md
git commit -m "feat(agents): community-adapter subagent"
```

---

## Phase 5 — Slash commands

### Task 18: `/research` slash command

**Files:**
- Create: `commands/research.md`

- [ ] **Step 1: Write the command file**

Create `commands/research.md`:

````markdown
---
description: Deep research on a URL (YouTube/arXiv/GitHub/blog/docs) or topic keyword. Produces research/YYYY-MM-DD-<slug>/README.md.
argument-hint: <URL or topic> [--yes] [--fresh] [--slug <name>]
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, WebFetch, WebSearch
---

## Inputs

`$ARGUMENTS` — raw argument string. Parse into:
- `target` (positional, required): URL or topic text
- `--yes`: skip Intent Q&A, engine infers
- `--fresh`: bypass cache
- `--slug <name>`: manual slug override

## Constants

- `PLUGIN_DIR` = the directory containing this command's plugin
- `RESEARCH_DIR` = `<project_cwd>/research`
- Date today: !`date -u +%Y-%m-%d`

## Pipeline

Execute these stages **in order**. Do not skip stages.

### Stage 1 — Classify

Run `bash "$PLUGIN_DIR/scripts/classify_url.sh" "<target>"`. Store the result as `input_type`.

### Stage 2 — Preview

Branch by `input_type`:

- **youtube** → `bash "$PLUGIN_DIR/scripts/yt_fetch.sh" metadata "<target>"` → parse title/description/chapters/selected_caption_lang. Extract roughly the first 5 minutes of the selected-lang captions by running `yt_fetch.sh captions` into a temporary dir (or reading cached VTT if it exists).
- **arxiv** → invoke the `huggingface-skills:hugging-face-paper-pages` skill with the arXiv id to get title+abstract.
- **github** → `gh repo view <owner>/<repo> --json ...` + first 2 KB of README.
- **huggingface** → `hf` CLI card summary.
- **blog / community** → `mcp firecrawl scrape` of the URL; take first 2 KB of markdown.
- **topic** → `WebSearch` with `<target>` and keep the top 5 result titles + snippets.

Write the preview to `RESEARCH_DIR/<tmp-slug>/cache/preview-<cache_key>.json` (create dir if needed). Compute `cache_key` via `bash "$PLUGIN_DIR/scripts/cache_key.sh" "<target>"`.

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

Dispatch each adapter with a single Agent call, parallel (issue all Agent tool calls in one assistant message). Per-adapter prompt template:

```
You are dispatched as the <adapter-name> subagent for research session <slug>.

Inputs:
  <JSON of {url|targets|libraries|thread_urls, intent, cache_dir, slug, fresh}>

Return a single fenced JSON block per lib/adapter_contract.md. Do not include anything after the JSON block.
```

Timeout per adapter: 5 minutes (configured implicitly by the agent runtime; do NOT actively retry beyond the single dispatch). If an adapter returns non-JSON or malformed JSON, record it as a failure and continue.

### Stage 5 — Synthesize & Persist

1. Collect adapter outputs. Re-number source ids across adapters into a single zero-indexed list `[1]…[N]`.
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
3. Write `<report_dir>/README.md` using the templates in `lib/report_sections.md`. Merge findings by topic, not by adapter. Dedupe near-duplicate findings. Preserve `[n]` markers.
4. YouTube only: write `<report_dir>/transcript.md` from the youtube-adapter `artifacts.transcript_md`.
5. For each unique `related[]` entry, write `<report_dir>/related/<kind>-<slug>.md` with a one-paragraph summary + URL. Deduplicate by URL.
6. If any adapter had non-empty `failures[]`, include the `## 수집 실패 (Failures)` section in README.md.
7. Final message to user: one line with `<report_dir>/README.md` path + a 2-line TL;DR preview.

## Cache policy

- Preview JSON is written under `<report_dir>/cache/preview-<cache_key>.json`.
- Each adapter receives `cache_dir = <report_dir>/cache/` in its inputs. Adapters MAY write `adapter-<name>-<cache_key>.json` for reuse.
- `--fresh` → ignore all cache for this run but still write fresh cache files.

## Failure policy

- Never abort the pipeline because a single adapter failed.
- If ALL adapters fail, still produce a skeleton report with preview content and a prominent Failures section.
- Missing `yt-dlp` on a youtube input → stop before Stage 2 with a clear error telling the user how to install.
````

- [ ] **Step 2: Smoke-check the file parses as a valid slash command**

Run: `head -5 commands/research.md`
Expected output starts with `---` and contains `description:`.

- [ ] **Step 3: Commit**

```bash
git add commands/research.md
git commit -m "feat(commands): /research slash command with 5-stage pipeline"
```

---

### Task 19: `/research-followup` slash command

**Files:**
- Create: `commands/research-followup.md`

- [ ] **Step 1: Write the followup command**

Create `commands/research-followup.md`:

````markdown
---
description: Follow up on the most recent research session (or a named one). Appends to research/<slug>/session.md.
argument-hint: [question] [--slug <name>] [--fresh]
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, WebFetch, WebSearch
---

## Inputs

`$ARGUMENTS` — parse into:
- `question` (positional, optional). If empty, ask the user "무엇을 추가로 알고 싶으세요?" and wait.
- `--slug <name>`
- `--fresh`

## Resolve session

- If `--slug` was provided, use it.
- Else run `bash "$PLUGIN_DIR/scripts/find_latest_session.sh" "<project_cwd>/research"` and use that slug.
- If no session exists, tell the user: "아직 리서치 세션이 없습니다. 먼저 `/research <target>`를 실행하세요." and stop.

Let `<report_dir> = <project_cwd>/research/<slug>`.

## Load context

Read:
- `<report_dir>/README.md`
- `<report_dir>/sources.json`
- `<report_dir>/intent.json`
- `<report_dir>/session.md` (if exists; create empty if not)

## Decide: new data needed?

Classify the user's question into one of:

- **A) Answerable from existing context** — no new fetches.
- **B) Needs new fetch** — examples: "X에 대한 비교 레포 찾아줘", "저자 배경 더", "이 영상의 다른 부분".
- **C) New related thread / paper / video** — user pastes a new URL.

For (B) and (C), dispatch 1–2 adapter subagents (same contract as `/research` Stage 4) with a tightly scoped prompt. Do NOT re-run the full fan-out.

## Answer

Compose the answer in Korean. Cite existing sources by their `[n]` number from `sources.json`. If new sources were fetched, append them to `sources.json` (continue numbering), write any new `related/*.md` files, and cite with the new `[n]`.

## Append to session.md

Append (append-only, never rewrite prior entries):

```markdown
---

## <ISO_timestamp> — <question, one line>

**질문**: <full question>

**답변**
<answer body with [n] citations>

**새 자료** (있을 때만)
- [{{title}}]({{url}}) — <one-line why>
```

## Report path

Final message: one line with `<report_dir>/session.md` path.
````

- [ ] **Step 2: Commit**

```bash
git add commands/research-followup.md
git commit -m "feat(commands): /research-followup slash command"
```

---

## Phase 6 — Install, end-to-end acceptance

### Task 20: Install plugin locally

**Files:**
- (no new files)

- [ ] **Step 1: Run install script**

```bash
./install.sh
```

Expected output: `Linked: /home/taejin/.claude/plugins/research-engine -> /home/taejin/projects/research-engine`

- [ ] **Step 2: Verify symlink**

```bash
ls -la ~/.claude/plugins/research-engine
```

Expected: a symlink pointing to the project directory.

- [ ] **Step 3: (Manual) Reload Claude Code plugins**

In a NEW Claude Code session, run `/plugins reload` or restart. Confirm `/research` appears in `/` autocomplete.

- [ ] **Step 4: Commit nothing (install is runtime-only)**

No commit needed for this task.

---

### Task 21: Write acceptance checklists

**Files:**
- Create: `tests/acceptance/youtube_url.md`
- Create: `tests/acceptance/arxiv_url.md`
- Create: `tests/acceptance/github_url.md`
- Create: `tests/acceptance/topic_input.md`
- Create: `tests/acceptance/followup_session.md`

- [ ] **Step 1: YouTube acceptance**

Create `tests/acceptance/youtube_url.md`:

```markdown
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
```

- [ ] **Step 2: arXiv acceptance**

Create `tests/acceptance/arxiv_url.md`:

```markdown
# Acceptance: arXiv URL

**Input:** `/research https://arxiv.org/abs/1706.03762`

## Expected

- [ ] Intent Q&A runs and I answer "학습용 / 방법론 중심 / 중급".
- [ ] Report has abstract summary, contributions, method summary, evaluation, limitations.
- [ ] `연관 자료 / 논문` lists 3+ related papers.
- [ ] `연관 자료 / 레포` includes at least one implementation repo (from HF paper page links or search fallback).
- [ ] No `transcript.md` is written.
```

- [ ] **Step 3: GitHub acceptance**

Create `tests/acceptance/github_url.md`:

```markdown
# Acceptance: GitHub repo URL

**Input:** `/research https://github.com/anthropics/claude-code`

## Expected

- [ ] README summary + stars/forks/last-push in `meta`.
- [ ] Findings cover: what it does, primary abstractions, notable design choices, activity signals.
- [ ] `연관 자료` includes linked sites / homepages from the README.
```

- [ ] **Step 4: Topic acceptance**

Create `tests/acceptance/topic_input.md`:

```markdown
# Acceptance: Topic keyword

**Input:** `/research "MoE LLM trends 2026"`

## Expected

- [ ] All 5 tier-1 adapters dispatched in parallel.
- [ ] Report cites at least 3 distinct adapters.
- [ ] `연관 자료` includes ≥3 papers, ≥2 repos, ≥2 blogs.
- [ ] Community section or citations from HN/Reddit when relevant.
```

- [ ] **Step 5: Followup acceptance**

Create `tests/acceptance/followup_session.md`:

```markdown
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
```

- [ ] **Step 6: Commit**

```bash
git add tests/acceptance/
git commit -m "test: acceptance checklists for /research and followup"
```

---

### Task 22: Run acceptance — YouTube golden path (real run)

**Files:**
- (no source file changes; produces `research/<slug>/...` under repo which is gitignored at `research/*/cache/` but the report files themselves should commit)

- [ ] **Step 1: Run `/research` on a short, known video**

In a Claude Code session with the plugin installed:

```
/research https://www.youtube.com/watch?v=dQw4w9WgXcQ
```

Answer Intent Q&A with: 학습용 / 개념 위주 / 입문.

- [ ] **Step 2: Walk the checklist**

Open `tests/acceptance/youtube_url.md` and tick off each item. Note any that fail.

- [ ] **Step 3: If failures, capture and fix**

For each failure:
1. Identify which stage (1-5) it occurred in.
2. Identify which file owns that stage (orchestrator `commands/research.md`, an adapter, or a script).
3. Fix the file. Re-run only the failing stage if possible (e.g., re-dispatch a single adapter), otherwise re-run from Stage 1 with `--fresh`.
4. Commit each fix with a dedicated message: `fix(<area>): <what>`.

- [ ] **Step 4: Note checklist result, do NOT commit acceptance artifacts**

`research/` is gitignored in this repo, so the generated report stays as a local artifact only. Simply record the result:

```bash
git commit --allow-empty -m "test(acceptance): YouTube golden path green"
```

---

### Task 23: Run acceptance — arXiv + GitHub + Topic + Followup

- [ ] **Step 1: arXiv acceptance**

Run `/research https://arxiv.org/abs/1706.03762` and walk `tests/acceptance/arxiv_url.md`. Fix any failures and commit.

- [ ] **Step 2: GitHub acceptance**

Run `/research https://github.com/anthropics/claude-code` and walk `tests/acceptance/github_url.md`. Fix and commit.

- [ ] **Step 3: Topic acceptance**

Run `/research "MoE LLM trends 2026"` and walk `tests/acceptance/topic_input.md`. Fix and commit.

- [ ] **Step 4: Followup acceptance**

Run both inputs in `tests/acceptance/followup_session.md` and tick the checklist. Fix and commit.

- [ ] **Step 5: Final commit**

After all four acceptance scenarios are green:

```bash
git commit --allow-empty -m "chore: all acceptance scenarios green"
```

---

## Phase 7 — Polish

### Task 24: Sweep all bats tests

- [ ] **Step 1: Run full bats suite**

```bash
bats tests/bats/
```

Expected: all previously written tests pass.

- [ ] **Step 2: If any regressions, fix the offending script and commit**

Commit message pattern: `fix(scripts/<name>): <what>`.

---

### Task 25: Final documentation pass

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add "Known limitations" to README.md**

Append to `README.md`:

```markdown
## Known limitations

- SNS(X, LinkedIn) 분석은 지원하지 않습니다.
- 페이월이 있는 블로그는 `status: failed` 로 기록됩니다.
- 라이브 스트리밍 / 미확정 자막 영상은 자막 확정 후만 지원.
- `/research-followup` 은 slug 자동 추적 시 가장 최근 mtime 세션을 선택. 여러 세션을 번갈아 쓴다면 `--slug` 를 명시.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: known limitations"
```

---

## Appendix A — Running the full test suite

```bash
# Shell unit tests
bats tests/bats/

# Manual acceptance (requires plugin installed + Claude Code session)
cat tests/acceptance/*.md
```

## Appendix B — Troubleshooting map

| Symptom | Likely file |
|---|---|
| `/research` not found in Claude Code | `install.sh`, `.claude-plugin/plugin.json` |
| Wrong URL classification | `scripts/classify_url.sh` |
| Weird slug | `scripts/slugify.sh` |
| Cache not reusing | `scripts/cache_key.sh` |
| Missing transcript | `scripts/yt_fetch.sh`, `agents/youtube-adapter.md` |
| Missing adapter JSON / parse error | `lib/adapter_contract.md`, the adapter's `.md` |
| Report section missing | `lib/report_sections.md`, synthesis step in `commands/research.md` |
| Followup targets wrong session | `scripts/find_latest_session.sh` |
