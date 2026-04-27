#!/usr/bin/env bash
# Push a research session directory to Notion.
#
# Design (2026-04-18 rewrite):
#   A single Notion DATABASE lives under NOTION_PARENT_PAGE_ID (title:
#   "research-engine"). Each research session is exactly ONE row in that
#   database. The row's properties capture metadata; the row's page body
#   is a consolidated report — README.md at the top, then toggle blocks
#   for transcript, followups, and related materials. No subpages.
#
# Page body layout:
#   [README.md rendered blocks]
#   ──── divider ────
#   ## 부속 자료
#   ▸ 📝 Transcript (toggle — transcript.md contents)
#   ▸ 💬 Followups  (toggle — session.md contents)
#   ▸ 🔗 Related    (toggle — related/*.md contents, one H3 per file)
#
# Idempotent: re-running a session (e.g. after a followup) clears the row's
# children and re-appends, so followup logs and new related files are synced.
#
# Usage:
#   push_to_notion.sh <report_dir>                   — push/update a session
#   push_to_notion.sh --archive-page <page_id>       — archive a Notion page (one-off cleanup)
#
# Required env (or ~/.config/research-engine/notion.env):
#   NOTION_TOKEN           Integration secret (from notion.so/profile/integrations)
#   NOTION_PARENT_PAGE_ID  32-char ID of page shared with the integration
# Optional env:
#   NOTION_DATABASE_ID     Cached database ID. Saves a search call.
#   NOTION_VERSION         Default "2022-06-28"
#   NOTION_API             Default "https://api.notion.com/v1"
#   DRY_RUN=1              Print API calls, make none.
set -euo pipefail

if [[ -z "${NOTION_TOKEN:-}" && -f "$HOME/.config/research-engine/notion.env" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.config/research-engine/notion.env"
fi
[[ -n "${NOTION_TOKEN:-}" ]] || { echo "push_to_notion: NOTION_TOKEN not set (see README)" >&2; exit 1; }

NOTION_VERSION="${NOTION_VERSION:-2022-06-28}"
NOTION_API="${NOTION_API:-https://api.notion.com/v1}"

# --- Sub-mode: archive a single page (one-off cleanup) ---
if [[ "${1:-}" == "--archive-page" && -n "${2:-}" ]]; then
  page_id="$2"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[DRY] PATCH /pages/${page_id} (archived: true)" >&2
    exit 0
  fi
  curl -sS -X PATCH "${NOTION_API}/pages/${page_id}" \
    -H "Authorization: Bearer ${NOTION_TOKEN}" \
    -H "Notion-Version: ${NOTION_VERSION}" \
    -H "Content-Type: application/json" \
    --data-binary @- <<< '{"archived": true}' \
    | jq '{id, archived, err: .code, msg: .message}'
  exit 0
fi

REPORT_DIR="${1:-}"
[[ -d "$REPORT_DIR" ]] || { echo "push_to_notion: invalid report dir: $REPORT_DIR" >&2; exit 2; }
[[ -n "${NOTION_PARENT_PAGE_ID:-}" ]] || { echo "push_to_notion: NOTION_PARENT_PAGE_ID not set" >&2; exit 1; }
SLUG="$(basename "$REPORT_DIR")"

# ----- API helper (token stays in env, never on argv) -----
_api() {
  # $1 method, $2 path, $3 optional json body
  local method="$1" path="$2" body="${3:-}"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[DRY] $method $path" >&2
    [[ -n "$body" ]] && { echo "$body" | jq -c '. | if type=="object" then (.properties // .filter // .) | keys? // keys? else . end' 2>/dev/null >&2 || true; }
    # Emit plausible fake responses based on path so flow continues
    case "$path" in
      /databases) echo '{"id":"dry-db-id"}' ;;
      /databases/*/query) echo '{"results":[]}' ;;
      /pages) echo '{"id":"dry-row-id","url":"https://www.notion.so/dry-row"}' ;;
      /blocks/*/children) echo '{"results":[]}' ;;
      /pages/*) echo '{"id":"dry-row-id","url":"https://www.notion.so/dry-row"}' ;;
      *) echo '{}' ;;
    esac
    return 0
  fi
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" "${NOTION_API}${path}" \
      -H "Authorization: Bearer ${NOTION_TOKEN}" \
      -H "Notion-Version: ${NOTION_VERSION}" \
      -H "Content-Type: application/json" \
      --data-binary @- <<< "$body"
  else
    curl -sS -X "$method" "${NOTION_API}${path}" \
      -H "Authorization: Bearer ${NOTION_TOKEN}" \
      -H "Notion-Version: ${NOTION_VERSION}"
  fi
}

# Upload a single local file to Notion via the file_uploads API (single_part
# mode, max 20MB). Echo the resulting file_upload id on stdout; empty on failure.
# Usage: notion_upload_file <local_path> <filename> <content_type>
NOTION_UPLOAD_VERSION="${NOTION_UPLOAD_VERSION:-2025-09-03}"
notion_upload_file() {
  local path="$1" filename="$2" ctype="$3"
  [[ -f "$path" ]] || { echo "notion_upload_file: not a file: $path" >&2; return 1; }
  local size
  size="$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null)"
  if (( size > 20 * 1024 * 1024 )); then
    echo "notion_upload_file: $filename is ${size} bytes (>20MB single-part limit); skipping" >&2
    return 1
  fi
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[DRY] POST /file_uploads + send $filename ($size bytes)" >&2
    echo "dry-run-file-upload-id"
    return 0
  fi
  local create_body create_resp upload_id upload_url send_resp
  create_body="$(jq -n --arg fn "$filename" --arg ct "$ctype" '{mode: "single_part", filename: $fn, content_type: $ct}')"
  create_resp="$(curl -sS -X POST "${NOTION_API}/file_uploads" \
    -H "Authorization: Bearer ${NOTION_TOKEN}" \
    -H "Notion-Version: ${NOTION_UPLOAD_VERSION}" \
    -H "Content-Type: application/json" \
    --data-binary "$create_body")"
  upload_id="$(jq -r '.id // empty' <<< "$create_resp")"
  upload_url="$(jq -r '.upload_url // empty' <<< "$create_resp")"
  if [[ -z "$upload_id" || -z "$upload_url" ]]; then
    echo "notion_upload_file: create_file_upload failed for $filename: $create_resp" >&2
    return 1
  fi
  send_resp="$(curl -sS -X POST "$upload_url" \
    -H "Authorization: Bearer ${NOTION_TOKEN}" \
    -H "Notion-Version: ${NOTION_UPLOAD_VERSION}" \
    -F "file=@${path};type=${ctype};filename=${filename}")"
  local status
  status="$(jq -r '.status // empty' <<< "$send_resp")"
  if [[ "$status" != "uploaded" ]]; then
    echo "notion_upload_file: send bytes failed for $filename: $send_resp" >&2
    return 1
  fi
  echo "$upload_id"
}

# ----- jq helpers that avoid MAX_ARG_STRLEN (131KB argv) on large JSON -----
#
# Linux caps a single argv entry at MAX_ARG_STRLEN (131072 bytes). Passing a
# multi-hundred-KB JSON blob via `jq --argjson NAME "$VAR"` therefore fails
# with "Argument list too long" once README + transcript + 20+ related files
# accumulate. Routing the blob through a process-substitution FD (from a
# `printf` *builtin*, which does not execve) keeps the blob in memory/pipes
# and jq sees only the `/dev/fd/N` path on argv.

jq_concat_arrays() {
  # Prints $1 + $2 where both are JSON array strings.
  jq -s '.[0] + .[1]' <(printf '%s' "$1") <(printf '%s' "$2")
}

jq_append_element() {
  # Prints $1 + [$2] where $1 is JSON array string, $2 is JSON value string.
  jq -s '.[0] + [.[1]]' <(printf '%s' "$1") <(printf '%s' "$2")
}

# ----- Select enum whitelists (match ensure_database schema below) -----
PURPOSE_ENUM="학습 의사결정 공유 기타"
AUDIENCE_ENUM="입문 중급 전문가"
INPUT_TYPE_ENUM="youtube arxiv github blog topic huggingface community"

_enum_match() {
  # $1=value, $2=space-delimited whitelist. Returns 0 if value is in whitelist.
  local val="$1" list="$2"
  [[ " $list " == *" $val "* ]]
}

# ----- Markdown → Notion blocks (python helper, shared) -----
# Python source is stored in a variable so `python3 -c` can execute it while
# keeping stdin free for the markdown input. An inline `python3 - <<PYEOF`
# heredoc would hijack stdin and leave the markdown unread.
PY_MD_TO_BLOCKS=$(cat <<'PYEOF'
import json, os, re, sys
md = sys.stdin.read()
blocks = []
in_code = False
code_lang = "plain text"
code_buf = []

# Image resolution context: if set, standalone ![alt](path) lines pointing at
# a local PNG whose neighbor .meta.json has a quickchart_url become Notion
# image blocks backed by that external URL (no file upload needed).
BASE_DIR = os.environ.get("NOTION_MD_BASE_DIR", "").strip() or None

# Map of relative-path → file_upload_id for locally-uploaded images (jpg/png/etc.).
# Populated by the bash side scan_and_upload_md_images() pass. Keys match the
# markdown reference string verbatim (i.e. "figures/frame-01-foo.jpg").
try:
    UPLOAD_MAP = json.loads(os.environ.get("NOTION_MD_UPLOAD_MAP", "") or "{}")
except Exception:
    UPLOAD_MAP = {}

# ---------- inline rich-text parser ----------
# Handles **bold**, *italic*, `code`, [text](url) within paragraph/heading/list/cell content.
# Chunks to 1900 chars to stay under Notion's 2000-char rich_text limit.
_INLINE_RE = re.compile(
    r"(\*\*[^*\n]+?\*\*)"      # bold
    r"|(`[^`\n]+?`)"            # inline code
    r"|(\[[^\]\n]+?\]\([^)\n]+?\))"  # link
    r"|(\*[^*\n]+?\*)"          # italic
)

def _rt_chunked(content, bold=False, italic=False, code=False, href=None):
    out = []
    s = content
    while s:
        chunk, s = s[:1900], s[1900:]
        text_obj = {"content": chunk}
        if href:
            text_obj["link"] = {"url": href}
        rt = {"type": "text", "text": text_obj}
        ann = {}
        if bold:   ann["bold"]   = True
        if italic: ann["italic"] = True
        if code:   ann["code"]   = True
        if ann:
            rt["annotations"] = ann
        out.append(rt)
    return out

def rtext(s):
    """Parse an inline markdown string into a Notion rich_text array."""
    out = []
    last = 0
    for m in _INLINE_RE.finditer(s):
        if m.start() > last:
            out.extend(_rt_chunked(s[last:m.start()]))
        tok = m.group(0)
        if tok.startswith("**") and tok.endswith("**"):
            out.extend(_rt_chunked(tok[2:-2], bold=True))
        elif tok.startswith("`") and tok.endswith("`"):
            out.extend(_rt_chunked(tok[1:-1], code=True))
        elif tok.startswith("["):
            lm = re.match(r"\[([^\]]+)\]\(([^)]+)\)", tok)
            if lm:
                out.extend(_rt_chunked(lm.group(1), href=lm.group(2)))
            else:
                out.extend(_rt_chunked(tok))
        elif tok.startswith("*") and tok.endswith("*"):
            out.extend(_rt_chunked(tok[1:-1], italic=True))
        else:
            out.extend(_rt_chunked(tok))
        last = m.end()
    if last < len(s):
        out.extend(_rt_chunked(s[last:]))
    if not out:
        out = [{"type": "text", "text": {"content": ""}}]
    return out

# ---------- callout detection ----------
# Blockquotes that start with a well-known emoji become Notion callouts with
# matching icon (and light background color where helpful), dramatically
# improving readability vs. plain gray quote bars.
CALLOUT_MAP = {
    "⚠️":  ("⚠️",  "yellow_background"),
    "❗":  ("❗",  "red_background"),
    "❌":  ("❌",  "red_background"),
    "✅":  ("✅",  "green_background"),
    "ℹ️":  ("ℹ️",  "blue_background"),
    "📒":  ("📒",  "gray_background"),
    "📝":  ("📝",  "gray_background"),
    "📸":  ("📸",  "purple_background"),
    "💡":  ("💡",  "yellow_background"),
    "🔗":  ("🔗",  "blue_background"),
    "🚨":  ("🚨",  "red_background"),
}

def match_callout(body_after_gt):
    for emoji, (icon, color) in CALLOUT_MAP.items():
        if body_after_gt.startswith(emoji + " "):
            return icon, color, body_after_gt[len(emoji)+1:]
        if body_after_gt.startswith(emoji):
            return icon, color, body_after_gt[len(emoji):].lstrip()
    return None

# ---------- pipe-table parser ----------
# A well-formed Markdown pipe table is:
#     | h1 | h2 |
#     | --- | --- |
#     | c1 | c2 |
# We buffer pending table state and flush when the table ends.

def is_table_line(line):
    s = line.strip()
    return s.startswith("|") and s.endswith("|") and len(s) > 1

def is_table_sep(line):
    return bool(re.match(r"^\s*\|?[\s:|-]+\|?\s*$", line)) and "-" in line and "|" in line

def split_row(line):
    s = line.strip()
    if s.startswith("|"): s = s[1:]
    if s.endswith("|"):   s = s[:-1]
    # Naive split — assume cell contents don't contain escaped |.
    return [c.strip() for c in s.split("|")]

def make_table_block(header, rows):
    width = len(header)
    children = []
    def _row(cells):
        while len(cells) < width: cells.append("")
        cells = cells[:width]
        return {
            "object": "block",
            "type": "table_row",
            "table_row": {"cells": [rtext(c) for c in cells]}
        }
    children.append(_row(header))
    for r in rows:
        children.append(_row(r))
    return {
        "object": "block",
        "type": "table",
        "table": {
            "table_width": width,
            "has_column_header": True,
            "has_row_header": False,
            "children": children
        }
    }

def flush_code():
    global code_buf, code_lang, in_code
    if code_buf:
        blocks.append({
            "object":"block","type":"code",
            "code": {"language": code_lang, "rich_text": rtext("\n".join(code_buf))}
        })
    code_buf = []; code_lang = "plain text"; in_code = False

def try_image_block(line):
    # Standalone image line: ![alt](path)  — no surrounding text.
    m = re.match(r"^\s*!\[([^\]]*)\]\(([^)]+)\)\s*$", line)
    if not m:
        return None
    alt = m.group(1).strip()
    path = m.group(2).strip()
    # Remote URL: use directly.
    if path.startswith("http://") or path.startswith("https://"):
        return {"object":"block","type":"image","image":{"type":"external","external":{"url":path},"caption": rtext(alt) if alt else []}}
    # Local path that was pre-uploaded via notion_upload_file (jpg/png/webp/gif).
    # Keyed by the exact markdown path string — scan_and_upload_md_images must
    # store the same form.
    up_id = UPLOAD_MAP.get(path)
    if up_id:
        return {"object":"block","type":"image","image":{"type":"file_upload","file_upload":{"id":up_id},"caption": rtext(alt) if alt else []}}
    # Local path: resolve via BASE_DIR and look up the adjacent .meta.json.
    if not BASE_DIR:
        return None
    abs_png = os.path.normpath(os.path.join(BASE_DIR, path))
    if not abs_png.endswith(".png"):
        return None
    meta_path = abs_png[:-4] + ".meta.json"
    if not os.path.isfile(meta_path):
        return None
    try:
        with open(meta_path, "r", encoding="utf-8") as f:
            meta = json.load(f)
        url = (meta.get("quickchart_url") or "").strip()
    except Exception:
        return None
    if not url or len(url) > 2000:
        return None
    return {"object":"block","type":"image","image":{"type":"external","external":{"url":url},"caption": rtext(alt) if alt else []}}

NOTION_LANGS = {"abap","arduino","bash","basic","c","clojure","coffeescript","c++","c#","css","dart","diff","docker","elixir","elm","erlang","flow","fortran","f#","gherkin","glsl","go","graphql","groovy","haskell","html","java","javascript","json","julia","kotlin","latex","less","lisp","livescript","lua","makefile","markdown","markup","matlab","mermaid","nix","objective-c","ocaml","pascal","perl","php","plain text","powershell","prolog","protobuf","python","r","reason","ruby","rust","sass","scala","scheme","scss","shell","solidity","sql","swift","typescript","vb.net","verilog","vhdl","visual basic","webassembly","xml","yaml"}

# ---------- main line loop with table lookahead ----------
lines = md.splitlines()
i = 0
N = len(lines)
while i < N:
    line = lines[i]

    # Inside a fenced code block: accumulate until closing ```
    if in_code:
        if line.startswith("```"):
            flush_code()
        else:
            code_buf.append(line)
        i += 1
        continue

    # Fenced code block opener
    m = re.match(r"^```(\w*)\s*$", line)
    if m:
        in_code = True
        code_lang = (m.group(1) or "plain text")
        if code_lang not in NOTION_LANGS: code_lang = "plain text"
        i += 1
        continue

    # Standalone image line
    img = try_image_block(line)
    if img is not None:
        blocks.append(img)
        i += 1
        continue

    # Pipe table — require "| ... |" followed by separator "| --- | ... |"
    if is_table_line(line) and i + 1 < N and is_table_sep(lines[i + 1]):
        header = split_row(line)
        j = i + 2
        rows = []
        while j < N and is_table_line(lines[j]) and not is_table_sep(lines[j]):
            rows.append(split_row(lines[j]))
            j += 1
        blocks.append(make_table_block(header, rows))
        i = j
        continue

    # Headings
    if line.startswith("### "):
        blocks.append({"object":"block","type":"heading_3","heading_3":{"rich_text":rtext(line[4:])}})
    elif line.startswith("## "):
        blocks.append({"object":"block","type":"heading_2","heading_2":{"rich_text":rtext(line[3:])}})
    elif line.startswith("# "):
        blocks.append({"object":"block","type":"heading_1","heading_1":{"rich_text":rtext(line[2:])}})

    # Horizontal rule
    elif re.match(r"^(\*\*\*|---)\s*$", line):
        blocks.append({"object":"block","type":"divider","divider":{}})

    # Blockquote → callout (if leading emoji) or plain quote
    elif line.startswith("> "):
        body = line[2:]
        hit = match_callout(body)
        if hit:
            icon, color, text = hit
            blocks.append({
                "object":"block","type":"callout",
                "callout": {
                    "rich_text": rtext(text),
                    "icon": {"type": "emoji", "emoji": icon},
                    "color": color
                }
            })
        else:
            blocks.append({"object":"block","type":"quote","quote":{"rich_text":rtext(body)}})

    # Bulleted list
    elif re.match(r"^\s*[-*]\s", line):
        blocks.append({"object":"block","type":"bulleted_list_item","bulleted_list_item":{"rich_text":rtext(re.sub(r"^\s*[-*]\s", "", line))}})

    # Numbered list
    elif re.match(r"^\s*\d+\.\s", line):
        blocks.append({"object":"block","type":"numbered_list_item","numbered_list_item":{"rich_text":rtext(re.sub(r"^\s*\d+\.\s", "", line))}})

    # Blank line
    elif line.strip() == "":
        pass

    # Default paragraph
    else:
        blocks.append({"object":"block","type":"paragraph","paragraph":{"rich_text":rtext(line)}})

    i += 1

if in_code: flush_code()
print(json.dumps(blocks))
PYEOF
)

md_to_blocks() { python3 -c "$PY_MD_TO_BLOCKS"; }

# Scan a markdown file for standalone local image references, upload each one
# to Notion via notion_upload_file(), and echo a JSON map {rel_path: upload_id}.
# Remote URLs are left alone. Chart PNGs with adjacent *.meta.json quickchart_url
# are skipped (they use the external-URL path via try_image_block).
# Supports jpg / jpeg / png / webp / gif. Skips files >20MB (single-part cap).
scan_and_upload_md_images() {
  local md_file="$1" base_dir="$2"
  [[ -f "$md_file" ]] || { echo '{}'; return 0; }
  local paths
  paths="$(python3 - "$md_file" <<'PYEOF'
import re, sys
md = open(sys.argv[1], 'r', encoding='utf-8').read()
seen = set()
for m in re.finditer(r'^\s*!\[[^\]]*\]\(([^)]+)\)\s*$', md, flags=re.M):
    p = m.group(1).strip()
    if p.startswith(('http://','https://')):
        continue
    if p in seen:
        continue
    seen.add(p)
    print(p)
PYEOF
  )"
  local map='{}'
  local rel abs filename ctype upload_id meta qc
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    abs="$(python3 -c "import os,sys; print(os.path.normpath(os.path.join(sys.argv[1], sys.argv[2])))" "$base_dir" "$rel")"
    [[ -f "$abs" ]] || { echo "push_to_notion: image not found, skipping: $rel" >&2; continue; }
    case "${rel,,}" in
      *.png)        ctype="image/png" ;;
      *.jpg|*.jpeg) ctype="image/jpeg" ;;
      *.webp)       ctype="image/webp" ;;
      *.gif)        ctype="image/gif" ;;
      *) continue ;;
    esac
    # Chart PNG with adjacent quickchart meta → let the quickchart fallback handle it.
    if [[ "${rel,,}" == *.png ]]; then
      meta="${abs%.png}.meta.json"
      if [[ -f "$meta" ]]; then
        qc="$(jq -r '.quickchart_url // empty' "$meta" 2>/dev/null || true)"
        [[ -n "$qc" ]] && continue
      fi
    fi
    filename="$(basename "$rel")"
    echo "push_to_notion: uploading $filename → Notion..." >&2
    upload_id="$(notion_upload_file "$abs" "$filename" "$ctype")" || { echo "push_to_notion: upload failed for $filename" >&2; continue; }
    [[ -n "$upload_id" ]] || continue
    map="$(jq --arg k "$rel" --arg v "$upload_id" '. + {($k): $v}' <<< "$map")"
  done <<< "$paths"
  echo "$map"
}

# Build a toggle block whose children are the parsed blocks of <file>
# Nested children are limited; large contents are truncated to 95 blocks (Notion cap for inline children).
toggle_from_file() {
  local title="$1" file="$2"
  [[ -f "$file" ]] || { echo '[]'; return 0; }
  local children
  children="$(md_to_blocks < "$file" | jq '.[0:95]')"
  # --slurpfile via process substitution — avoids argv size limit on $children.
  jq --slurpfile c <(printf '%s' "$children") --arg t "$title" -n '{
    object:"block", type:"toggle",
    toggle: {
      rich_text: [{ type:"text", text:{ content:$t } }],
      children: $c[0]
    }
  }'
}

# Toggle block wrapping multiple files (related/*) — inserts a H3 per file
toggle_from_related_dir() {
  local title="$1" dir="$2"
  [[ -d "$dir" ]] || { echo 'null'; return 0; }
  local combined="[]"
  local f name file_blocks
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f" .md)"
    # Each single-file block array is small (<10KB), so --argjson is safe here.
    file_blocks="$(
      jq -n --arg name "$name" --argjson body "$(md_to_blocks < "$f")" '
        [ { object:"block", type:"heading_3", heading_3:{ rich_text:[{ type:"text", text:{ content:$name } }] } } ]
        + $body
        + [ { object:"block", type:"divider", divider:{} } ]
      '
    )"
    # The accumulator `combined` grows across iterations and can exceed 131KB
    # with 20+ related files — route through FDs instead of argv.
    combined="$(jq_concat_arrays "$combined" "$file_blocks")"
  done
  # Cap inline nested to 95 blocks (Notion rejects more as direct children in one call)
  combined="$(jq '.[0:95]' <<< "$combined")"
  [[ "$(jq 'length' <<< "$combined")" -eq 0 ]] && { echo 'null'; return 0; }
  jq --slurpfile c <(printf '%s' "$combined") --arg t "$title" -n '{
    object:"block", type:"toggle",
    toggle: {
      rich_text: [{ type:"text", text:{ content:$t } }],
      children: $c[0]
    }
  }'
}

append_blocks_chunked() {
  # $1 page_id, stdin: JSON array.
  # Each 90-block chunk can still be 100KB+ (a single toggle with 95 inlined
  # transcript paragraphs is huge), so route the chunk through --slurpfile +
  # process substitution instead of --argjson to stay under MAX_ARG_STRLEN.
  local page_id="$1" blocks total i=0 chunk body
  blocks="$(cat)"
  total="$(jq 'length' <<< "$blocks")"
  while (( i < total )); do
    chunk="$(jq ".[${i}:$((i+90))]" <<< "$blocks")"
    body="$(jq --slurpfile c <(printf '%s' "$chunk") -n '{children: $c[0]}')"
    _api PATCH "/blocks/${page_id}/children" "$body" > /dev/null
    i=$((i+90))
  done
}

# ----- Metadata extraction -----
extract_intent() {
  # Reads intent.json (if present), prints "purpose|audience_level"
  local f="$REPORT_DIR/intent.json"
  if [[ -f "$f" ]]; then
    jq -r '"\(.purpose // "")|\(.audience_level // "")"' "$f"
  else
    echo "|"
  fi
}

extract_sources_meta() {
  # Reads sources.json (if present), prints "input_url|input_type|created|count"
  local f="$REPORT_DIR/sources.json"
  if [[ -f "$f" ]]; then
    jq -r '"\(.input // "")|\(.input_type // "")|\(.created // "")|\(.sources | length)"' "$f"
  else
    echo "||${SLUG}|0"
  fi
}

extract_title() {
  # Prefer frontmatter title in README.md, fall back to slug
  local f="$REPORT_DIR/README.md" t=""
  if [[ -f "$f" ]]; then
    t="$(awk '/^---$/{n++; next} n==1 && /^title:/{sub(/^title:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit}' "$f")"
  fi
  [[ -n "$t" ]] || t="$SLUG"
  printf '%s' "$t"
}

# ----- 1. Ensure database -----
ensure_database() {
  # Returns database ID on stdout. Uses cache > search > create.
  if [[ -n "${NOTION_DATABASE_ID:-}" ]]; then
    echo "$NOTION_DATABASE_ID"; return
  fi
  local body search_res hit
  body='{"query":"research-engine","filter":{"property":"object","value":"database"}}'
  search_res="$(_api POST /search "$body")"
  hit="$(jq -r --arg p "$NOTION_PARENT_PAGE_ID" '
    .results // [] | map(select(.parent.type == "page_id" and (.parent.page_id | gsub("-"; "")) == ($p | gsub("-"; ""))))
    | .[0].id // empty' <<< "$search_res")"
  if [[ -n "$hit" ]]; then
    echo "$hit"; return
  fi
  # Create database
  local create_body
  create_body="$(jq -n --arg p "$NOTION_PARENT_PAGE_ID" '{
    parent: { type: "page_id", page_id: $p },
    title: [{ type:"text", text:{ content:"research-engine" } }],
    properties: {
      "Title":    { title: {} },
      "Slug":     { rich_text: {} },
      "Input URL":{ url: {} },
      "Input Type": { select: { options: [
        {name:"youtube", color:"red"}, {name:"arxiv", color:"yellow"},
        {name:"github", color:"gray"}, {name:"blog", color:"blue"},
        {name:"topic", color:"green"}, {name:"huggingface", color:"orange"},
        {name:"community", color:"purple"}
      ] } },
      "Created":  { date: {} },
      "Purpose":  { select: { options: [
        {name:"학습", color:"blue"}, {name:"의사결정", color:"orange"},
        {name:"공유", color:"green"}, {name:"기타", color:"default"}
      ] } },
      "Audience": { select: { options: [
        {name:"입문", color:"gray"}, {name:"중급", color:"yellow"},
        {name:"전문가", color:"red"}
      ] } },
      "Sources":  { number: { format:"number" } }
    }
  }')"
  local res
  res="$(_api POST /databases "$create_body")"
  jq -r '.id // empty' <<< "$res"
}

# ----- 2. Find or create row by slug -----
find_row_by_slug() {
  # $1 = db_id
  local db_id="$1"
  local body
  body="$(jq -n --arg s "$SLUG" '{
    filter: { property: "Slug", rich_text: { equals: $s } },
    page_size: 1
  }')"
  local res
  res="$(_api POST "/databases/${db_id}/query" "$body")"
  jq -r '.results // [] | .[0].id // empty' <<< "$res"
}

clear_page_children() {
  # $1 = page_id; archives every existing child.
  #
  # We DO NOT paginate with start_cursor here. Notion's cursor points at an
  # absolute position in the original, pre-deletion list — after we DELETE
  # (= archive) the first page's blocks, reusing the old cursor can return
  # duplicate or stale pages, leaving some blocks un-archived. Instead we
  # keep fetching "page 1" until `results` comes back empty: each call
  # returns the next 100 still-active blocks from the top.
  #
  # Notion throttles at ~3 req/s per integration. Unthrottled delete loops
  # drop requests silently, which is exactly the symptom that left stale
  # blocks behind on the previous version. We DELETE with retry + a small
  # sleep between calls to stay under the rate limit.
  local page_id="$1" res chunk id count guard=0 status attempts
  while :; do
    res="$(_api GET "/blocks/${page_id}/children?page_size=100")"
    chunk="$(jq -c '.results // []' <<< "$res")"
    count="$(jq 'length' <<< "$chunk")"
    (( count == 0 )) && break
    for id in $(jq -r '.[].id' <<< "$chunk"); do
      attempts=0
      while (( attempts < 3 )); do
        status="$(
          curl -sS -o /dev/null -w '%{http_code}' -X DELETE \
            "${NOTION_API}/blocks/${id}" \
            -H "Authorization: Bearer ${NOTION_TOKEN}" \
            -H "Notion-Version: ${NOTION_VERSION}" || echo 000
        )"
        case "$status" in
          2*) break ;;
          404|409) break ;;                       # already archived — treat as success
          429|5*) sleep 1; attempts=$((attempts+1)) ;;   # retryable
          *)     sleep 0.3; attempts=$((attempts+1)) ;;  # other error — retry a couple of times
        esac
      done
      sleep 0.25  # stay under Notion's ~3 req/s integration cap
    done
    guard=$((guard+1))
    if (( guard > 50 )); then
      echo "push_to_notion: clear_page_children guard tripped — stopping at $guard iterations" >&2
      break
    fi
  done
}

# ----- 3. Build row properties JSON -----
build_row_props() {
  local title="$1" purpose="$2" audience="$3" input_url="$4" input_type="$5" created="$6" sources_count="$7"
  # Required: Title (type: title). Others optional — include only when non-empty
  # AND (for select properties) when the value is in the database's enum set.
  # Notion select rejects any value not in options AND rejects values with
  # commas — so we whitelist-validate rather than passing free-form intent text.
  local created_prop='null'
  [[ -n "$created" ]] && created_prop="$(jq -n --arg d "$created" '{ date: { start: $d } }')"
  local input_type_prop='null'
  if [[ -n "$input_type" ]]; then
    if _enum_match "$input_type" "$INPUT_TYPE_ENUM"; then
      input_type_prop="$(jq -n --arg t "$input_type" '{ select: { name: $t } }')"
    else
      echo "push_to_notion: warn: input_type='$input_type' not in {$INPUT_TYPE_ENUM}, omitting" >&2
    fi
  fi
  local purpose_prop='null'
  if [[ -n "$purpose" ]]; then
    if _enum_match "$purpose" "$PURPOSE_ENUM"; then
      purpose_prop="$(jq -n --arg t "$purpose" '{ select: { name: $t } }')"
    else
      echo "push_to_notion: warn: purpose='$purpose' not in {$PURPOSE_ENUM}, omitting" >&2
    fi
  fi
  local audience_prop='null'
  if [[ -n "$audience" ]]; then
    if _enum_match "$audience" "$AUDIENCE_ENUM"; then
      audience_prop="$(jq -n --arg t "$audience" '{ select: { name: $t } }')"
    else
      echo "push_to_notion: warn: audience='$audience' not in {$AUDIENCE_ENUM}, omitting" >&2
    fi
  fi
  local url_prop='null'
  [[ -n "$input_url" ]] && url_prop="$(jq -n --arg u "$input_url" '{ url: $u }')"
  jq -n \
    --arg title "$title" --arg slug "$SLUG" \
    --argjson created "$created_prop" --argjson itype "$input_type_prop" \
    --argjson purpose "$purpose_prop" --argjson audience "$audience_prop" \
    --argjson url "$url_prop" --argjson n "$sources_count" '
    {
      "Title": { title: [{ type:"text", text:{ content:$title } }] },
      "Slug":  { rich_text: [{ type:"text", text:{ content:$slug } }] },
      "Sources": { number: $n }
    }
    + (if $url.url then {"Input URL": $url} else {} end)
    + (if $itype.select then {"Input Type": $itype} else {} end)
    + (if $created.date then {"Created": $created} else {} end)
    + (if $purpose.select then {"Purpose": $purpose} else {} end)
    + (if $audience.select then {"Audience": $audience} else {} end)
  '
}

# ----- Main -----

echo "push_to_notion: session=$SLUG" >&2

DB_ID="$(ensure_database)"
[[ -n "$DB_ID" ]] || { echo "push_to_notion: failed to resolve database" >&2; exit 1; }
echo "push_to_notion: database id=$DB_ID" >&2

ROW_ID="$(find_row_by_slug "$DB_ID")"

INTENT="$(extract_intent)"
PURPOSE="${INTENT%|*}"; AUDIENCE="${INTENT#*|}"
SMETA="$(extract_sources_meta)"
IFS='|' read -r INPUT_URL INPUT_TYPE CREATED SOURCES_COUNT <<< "$SMETA"
# Created -> date-only (YYYY-MM-DD) since we use date property, not datetime
CREATED_DATE="${CREATED%%T*}"
TITLE="$(extract_title)"

PROPS="$(build_row_props "$TITLE" "$PURPOSE" "$AUDIENCE" "$INPUT_URL" "$INPUT_TYPE" "$CREATED_DATE" "$SOURCES_COUNT")"

if [[ -z "$ROW_ID" ]]; then
  # Create row
  CREATE_BODY="$(jq -n --arg db "$DB_ID" --argjson props "$PROPS" '{
    parent: { database_id: $db },
    properties: $props
  }')"
  RES="$(_api POST /pages "$CREATE_BODY")"
  ROW_ID="$(jq -r '.id // empty' <<< "$RES")"
  [[ -n "$ROW_ID" ]] || { echo "push_to_notion: failed to create row: $RES" >&2; exit 1; }
  echo "push_to_notion: created row id=$ROW_ID" >&2
else
  # Update properties
  UPDATE_BODY="$(jq -n --argjson props "$PROPS" '{ properties: $props }')"
  _api PATCH "/pages/${ROW_ID}" "$UPDATE_BODY" > /dev/null
  echo "push_to_notion: updating existing row id=$ROW_ID (clearing children)" >&2
  clear_page_children "$ROW_ID"
fi

# ----- Build consolidated body -----
# Pre-upload any local image references in README.md (jpg/png/webp/gif) so
# try_image_block() can render them as Notion file_upload image blocks.
UPLOAD_MAP="$(scan_and_upload_md_images "$REPORT_DIR/README.md" "$REPORT_DIR")"
BODY_BLOCKS="$(NOTION_MD_BASE_DIR="$REPORT_DIR" NOTION_MD_UPLOAD_MAP="$UPLOAD_MAP" md_to_blocks < "$REPORT_DIR/README.md" 2>/dev/null || echo '[]')"

# Attach slide deck artifacts produced by /research-visualize --slides.
# Upload .pptx and .pdf via the file_uploads API and append as file blocks
# under a "📎 슬라이드 덱" heading.
SLIDE_BLOCKS='[]'
add_slide_block() {
  local path="$1" filename="$2" ctype="$3" label="$4"
  [[ -f "$path" ]] || return 0
  echo "push_to_notion: uploading $filename → Notion..." >&2
  local upload_id
  upload_id="$(notion_upload_file "$path" "$filename" "$ctype")" || return 0
  [[ -n "$upload_id" ]] || return 0
  local blk
  blk="$(jq -n --arg id "$upload_id" --arg cap "$label" '{
    object: "block",
    type: "file",
    file: {
      type: "file_upload",
      file_upload: { id: $id },
      caption: [{ type: "text", text: { content: $cap } }]
    }
  }')"
  SLIDE_BLOCKS="$(jq --argjson b "$blk" '. + [$b]' <<< "$SLIDE_BLOCKS")"
}

add_slide_block "$REPORT_DIR/slides.pptx" "${SLUG}.pptx" \
  "application/vnd.openxmlformats-officedocument.presentationml.presentation" \
  "PowerPoint / Keynote 편집용"
add_slide_block "$REPORT_DIR/slides.pdf" "${SLUG}.pdf" \
  "application/pdf" \
  "빠른 미리보기용 PDF"

# All BODY_BLOCKS concatenations below route through FDs (via jq_* helpers)
# because the running blob accumulates README + transcript + related + session
# and easily crosses MAX_ARG_STRLEN (131KB).
if [[ "$(jq 'length' <<< "$SLIDE_BLOCKS")" != "0" ]]; then
  SLIDE_HEADER_BLOCKS='[
    { "object":"block","type":"divider","divider":{} },
    { "object":"block","type":"heading_2","heading_2":{"rich_text":[{"type":"text","text":{"content":"📎 슬라이드 덱"}}]} }
  ]'
  BODY_BLOCKS="$(jq_concat_arrays "$BODY_BLOCKS" "$SLIDE_HEADER_BLOCKS")"
  BODY_BLOCKS="$(jq_concat_arrays "$BODY_BLOCKS" "$SLIDE_BLOCKS")"
fi

# Divider + "부속 자료" heading before the toggles (if any attachment exists)
HAS_ATTACH=0
[[ -f "$REPORT_DIR/transcript.md" ]] && HAS_ATTACH=1
[[ -f "$REPORT_DIR/session.md"    ]] && HAS_ATTACH=1
[[ -d "$REPORT_DIR/related"       ]] && HAS_ATTACH=1

if (( HAS_ATTACH )); then
  EXTRA_BLOCKS='[
    { "object":"block","type":"divider","divider":{} },
    { "object":"block","type":"heading_2","heading_2":{"rich_text":[{"type":"text","text":{"content":"부속 자료"}}]} }
  ]'
  BODY_BLOCKS="$(jq_concat_arrays "$BODY_BLOCKS" "$EXTRA_BLOCKS")"
fi

if [[ -f "$REPORT_DIR/transcript.md" ]]; then
  T="$(toggle_from_file "📝 Transcript" "$REPORT_DIR/transcript.md")"
  BODY_BLOCKS="$(jq_append_element "$BODY_BLOCKS" "$T")"
fi
if [[ -f "$REPORT_DIR/session.md" ]]; then
  T="$(toggle_from_file "💬 Followups" "$REPORT_DIR/session.md")"
  BODY_BLOCKS="$(jq_append_element "$BODY_BLOCKS" "$T")"
fi
if [[ -d "$REPORT_DIR/related" ]]; then
  T="$(toggle_from_related_dir "🔗 Related materials" "$REPORT_DIR/related")"
  if [[ "$T" != "null" ]]; then
    BODY_BLOCKS="$(jq_append_element "$BODY_BLOCKS" "$T")"
  fi
fi

append_blocks_chunked "$ROW_ID" <<< "$BODY_BLOCKS"
echo "push_to_notion: wrote $(jq 'length' <<< "$BODY_BLOCKS") top-level blocks" >&2

# Emit row URL
URL="$(_api GET "/pages/${ROW_ID}" | jq -r '.url // empty')"
[[ -n "$URL" ]] || URL="https://www.notion.so/${ROW_ID//-/}"
echo "$URL"
