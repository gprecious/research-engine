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

# ----- Markdown → Notion blocks (python helper, shared) -----
# Python source is stored in a variable so `python3 -c` can execute it while
# keeping stdin free for the markdown input. An inline `python3 - <<PYEOF`
# heredoc would hijack stdin and leave the markdown unread.
PY_MD_TO_BLOCKS=$(cat <<'PYEOF'
import json, re, sys
md = sys.stdin.read()
blocks = []
in_code = False
code_lang = "plain text"
code_buf = []

def rtext(s):
    out = []
    while s:
        chunk, s = s[:1900], s[1900:]
        out.append({"type": "text", "text": {"content": chunk}})
    if not out:
        out = [{"type": "text", "text": {"content": ""}}]
    return out

def flush_code():
    global code_buf, code_lang, in_code
    if code_buf:
        blocks.append({
            "object":"block","type":"code",
            "code": {"language": code_lang, "rich_text": rtext("\n".join(code_buf))}
        })
    code_buf = []; code_lang = "plain text"; in_code = False

NOTION_LANGS = {"abap","arduino","bash","basic","c","clojure","coffeescript","c++","c#","css","dart","diff","docker","elixir","elm","erlang","flow","fortran","f#","gherkin","glsl","go","graphql","groovy","haskell","html","java","javascript","json","julia","kotlin","latex","less","lisp","livescript","lua","makefile","markdown","markup","matlab","mermaid","nix","objective-c","ocaml","pascal","perl","php","plain text","powershell","prolog","protobuf","python","r","reason","ruby","rust","sass","scala","scheme","scss","shell","solidity","sql","swift","typescript","vb.net","verilog","vhdl","visual basic","webassembly","xml","yaml"}

for line in md.splitlines():
    if in_code:
        if line.startswith("```"):
            flush_code()
        else:
            code_buf.append(line)
        continue
    m = re.match(r"^```(\w*)\s*$", line)
    if m:
        in_code = True
        code_lang = (m.group(1) or "plain text")
        if code_lang not in NOTION_LANGS: code_lang = "plain text"
        continue
    if line.startswith("### "):
        blocks.append({"object":"block","type":"heading_3","heading_3":{"rich_text":rtext(line[4:])}})
    elif line.startswith("## "):
        blocks.append({"object":"block","type":"heading_2","heading_2":{"rich_text":rtext(line[3:])}})
    elif line.startswith("# "):
        blocks.append({"object":"block","type":"heading_1","heading_1":{"rich_text":rtext(line[2:])}})
    elif re.match(r"^(\*\*\*|---)\s*$", line):
        blocks.append({"object":"block","type":"divider","divider":{}})
    elif line.startswith("> "):
        blocks.append({"object":"block","type":"quote","quote":{"rich_text":rtext(line[2:])}})
    elif re.match(r"^\s*[-*]\s", line):
        blocks.append({"object":"block","type":"bulleted_list_item","bulleted_list_item":{"rich_text":rtext(re.sub(r"^\s*[-*]\s", "", line))}})
    elif re.match(r"^\s*\d+\.\s", line):
        blocks.append({"object":"block","type":"numbered_list_item","numbered_list_item":{"rich_text":rtext(re.sub(r"^\s*\d+\.\s", "", line))}})
    elif line.strip() == "":
        continue
    else:
        blocks.append({"object":"block","type":"paragraph","paragraph":{"rich_text":rtext(line)}})

if in_code: flush_code()
print(json.dumps(blocks))
PYEOF
)

md_to_blocks() { python3 -c "$PY_MD_TO_BLOCKS"; }

# Build a toggle block whose children are the parsed blocks of <file>
# Nested children are limited; large contents are truncated to 95 blocks (Notion cap for inline children).
toggle_from_file() {
  local title="$1" file="$2"
  [[ -f "$file" ]] || { echo '[]'; return 0; }
  local children
  children="$(md_to_blocks < "$file" | jq '.[0:95]')"
  jq -n --arg t "$title" --argjson c "$children" '{
    object:"block", type:"toggle",
    toggle: {
      rich_text: [{ type:"text", text:{ content:$t } }],
      children: $c
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
    file_blocks="$(
      jq -n --arg name "$name" --argjson body "$(md_to_blocks < "$f")" '
        [ { object:"block", type:"heading_3", heading_3:{ rich_text:[{ type:"text", text:{ content:$name } }] } } ]
        + $body
        + [ { object:"block", type:"divider", divider:{} } ]
      '
    )"
    combined="$(jq --argjson a "$combined" --argjson b "$file_blocks" -n '$a + $b')"
  done
  # Cap inline nested to 95 blocks (Notion rejects more as direct children in one call)
  combined="$(jq '.[0:95]' <<< "$combined")"
  [[ "$(jq 'length' <<< "$combined")" -eq 0 ]] && { echo 'null'; return 0; }
  jq -n --arg t "$title" --argjson c "$combined" '{
    object:"block", type:"toggle",
    toggle: {
      rich_text: [{ type:"text", text:{ content:$t } }],
      children: $c
    }
  }'
}

append_blocks_chunked() {
  # $1 page_id, stdin: JSON array
  local page_id="$1" blocks total i=0 chunk body
  blocks="$(cat)"
  total="$(jq 'length' <<< "$blocks")"
  while (( i < total )); do
    chunk="$(jq ".[${i}:$((i+90))]" <<< "$blocks")"
    body="$(jq -n --argjson c "$chunk" '{children: $c}')"
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
  # $1 = page_id; deletes all existing children (archive via DELETE)
  local page_id="$1" next_cursor="" chunk id
  while :; do
    local path="/blocks/${page_id}/children?page_size=100"
    [[ -n "$next_cursor" ]] && path="${path}&start_cursor=${next_cursor}"
    local res
    res="$(_api GET "$path")"
    chunk="$(jq -c '.results // []' <<< "$res")"
    for id in $(jq -r '.[].id' <<< "$chunk"); do
      _api DELETE "/blocks/${id}" > /dev/null || true
    done
    if [[ "$(jq -r '.has_more' <<< "$res")" != "true" ]]; then break; fi
    next_cursor="$(jq -r '.next_cursor' <<< "$res")"
  done
}

# ----- 3. Build row properties JSON -----
build_row_props() {
  local title="$1" purpose="$2" audience="$3" input_url="$4" input_type="$5" created="$6" sources_count="$7"
  # Required: Title (type: title). Others optional — include only when non-empty.
  local created_prop='null'
  [[ -n "$created" ]] && created_prop="$(jq -n --arg d "$created" '{ date: { start: $d } }')"
  local input_type_prop='null'
  [[ -n "$input_type" ]] && input_type_prop="$(jq -n --arg t "$input_type" '{ select: { name: $t } }')"
  local purpose_prop='null'
  [[ -n "$purpose" ]] && purpose_prop="$(jq -n --arg t "$purpose" '{ select: { name: $t } }')"
  local audience_prop='null'
  [[ -n "$audience" ]] && audience_prop="$(jq -n --arg t "$audience" '{ select: { name: $t } }')"
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
BODY_BLOCKS="$(md_to_blocks < "$REPORT_DIR/README.md" 2>/dev/null || echo '[]')"

# Divider + "부속 자료" heading before the toggles (if any attachment exists)
HAS_ATTACH=0
[[ -f "$REPORT_DIR/transcript.md" ]] && HAS_ATTACH=1
[[ -f "$REPORT_DIR/session.md"    ]] && HAS_ATTACH=1
[[ -d "$REPORT_DIR/related"       ]] && HAS_ATTACH=1

if (( HAS_ATTACH )); then
  BODY_BLOCKS="$(jq --argjson extra '[
    { "object":"block","type":"divider","divider":{} },
    { "object":"block","type":"heading_2","heading_2":{"rich_text":[{"type":"text","text":{"content":"부속 자료"}}]} }
  ]' -n --argjson b "$BODY_BLOCKS" '$b + $extra')"
fi

if [[ -f "$REPORT_DIR/transcript.md" ]]; then
  T="$(toggle_from_file "📝 Transcript" "$REPORT_DIR/transcript.md")"
  BODY_BLOCKS="$(jq --argjson t "$T" -n --argjson b "$BODY_BLOCKS" '$b + [$t]')"
fi
if [[ -f "$REPORT_DIR/session.md" ]]; then
  T="$(toggle_from_file "💬 Followups" "$REPORT_DIR/session.md")"
  BODY_BLOCKS="$(jq --argjson t "$T" -n --argjson b "$BODY_BLOCKS" '$b + [$t]')"
fi
if [[ -d "$REPORT_DIR/related" ]]; then
  T="$(toggle_from_related_dir "🔗 Related materials" "$REPORT_DIR/related")"
  if [[ "$T" != "null" ]]; then
    BODY_BLOCKS="$(jq --argjson t "$T" -n --argjson b "$BODY_BLOCKS" '$b + [$t]')"
  fi
fi

append_blocks_chunked "$ROW_ID" <<< "$BODY_BLOCKS"
echo "push_to_notion: wrote $(jq 'length' <<< "$BODY_BLOCKS") top-level blocks" >&2

# Emit row URL
URL="$(_api GET "/pages/${ROW_ID}" | jq -r '.url // empty')"
[[ -n "$URL" ]] || URL="https://www.notion.so/${ROW_ID//-/}"
echo "$URL"
