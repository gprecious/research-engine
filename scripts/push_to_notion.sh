#!/usr/bin/env bash
# Push a research session directory to Notion. Creates/updates pages under a
# designated parent page, mirroring the local directory structure.
#
# Layout on Notion:
#   <parent>/
#     research-engine/
#       <slug>/
#         (main page: README.md content)
#         ├── transcript (child page)
#         ├── session (child page)
#         └── related/<kind>-<slug> (child pages)
#
# Usage:
#   push_to_notion.sh <report_dir>
#
# Env required:
#   NOTION_TOKEN           Integration token from https://notion.so/profile/integrations
#                          (also supported: ~/.config/research-engine/notion.env → NOTION_TOKEN=...)
#   NOTION_PARENT_PAGE_ID  Page ID of the Notion page you shared with the integration.
#                          (32-char UUID, dashes optional). This is where the "research-engine"
#                          root page lives. The integration must have access.
#
# Optional env:
#   NOTION_ROOT_PAGE_ID    Cached ID of the auto-created "research-engine" root page.
#                          If set and valid, skips root creation; otherwise the script
#                          creates it under NOTION_PARENT_PAGE_ID and prints the id to stderr.
#   NOTION_VERSION         Notion API version, default "2022-06-28".
#   NOTION_API             API base, default "https://api.notion.com/v1".
#   DRY_RUN=1              Print what would be done, make no API calls.
set -euo pipefail

REPORT_DIR="${1:-}"
[[ -d "$REPORT_DIR" ]] || { echo "push_to_notion: invalid report dir: $REPORT_DIR" >&2; exit 2; }

# Load token file if present
if [[ -z "${NOTION_TOKEN:-}" && -f "$HOME/.config/research-engine/notion.env" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.config/research-engine/notion.env"
fi

[[ -n "${NOTION_TOKEN:-}" ]] || {
  cat >&2 <<'EOF'
push_to_notion: NOTION_TOKEN not set.

One-time setup:
  1. Create an integration at https://www.notion.so/profile/integrations
     (Internal integration, grant "Insert content" + "Update content")
  2. Copy the Internal Integration Secret.
  3. In Notion, share the target parent page with this integration:
     (parent page) → ••• → Add connection → pick the integration
  4. Put the token somewhere safe:
       mkdir -p ~/.config/research-engine
       printf 'NOTION_TOKEN=secret_XXX\nNOTION_PARENT_PAGE_ID=YYY\n' \
         > ~/.config/research-engine/notion.env
       chmod 600 ~/.config/research-engine/notion.env
  5. NOTION_PARENT_PAGE_ID is the 32-char ID in the shared page's URL.
EOF
  exit 1
}
[[ -n "${NOTION_PARENT_PAGE_ID:-}" ]] || { echo "push_to_notion: NOTION_PARENT_PAGE_ID not set." >&2; exit 1; }

NOTION_VERSION="${NOTION_VERSION:-2022-06-28}"
NOTION_API="${NOTION_API:-https://api.notion.com/v1}"

# ----- API helpers -----

_api() {
  # $1 = method, $2 = path, $3 = optional JSON body
  local method="$1" path="$2" body="${3:-}"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[DRY] $method $path" >&2
    [[ -n "$body" ]] && echo "$body" | head -c 400 >&2
    echo >&2
    echo '{"id":"dry-run-page-id","url":"https://www.notion.so/dry-run"}'
    return 0
  fi
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" "${NOTION_API}${path}" \
      -H "Authorization: Bearer ${NOTION_TOKEN}" \
      -H "Notion-Version: ${NOTION_VERSION}" \
      -H "Content-Type: application/json" \
      --data "$body"
  else
    curl -sS -X "$method" "${NOTION_API}${path}" \
      -H "Authorization: Bearer ${NOTION_TOKEN}" \
      -H "Notion-Version: ${NOTION_VERSION}"
  fi
}

create_page() {
  # $1 = parent_id, $2 = title, $3 = blocks_json_array
  local parent="$1" title="$2" blocks="$3" body
  body="$(jq -n --arg p "$parent" --arg t "$title" --argjson blocks "$blocks" '{
    parent: { page_id: $p },
    properties: { title: { title: [ { text: { content: $t } } ] } },
    children: $blocks
  }')"
  _api POST /pages "$body"
}

# Markdown → Notion blocks (coarse). Handles: H1/H2/H3, paragraphs, bulleted/numbered
# lists, blockquotes, fenced code blocks, horizontal rules, and plain inline markdown.
# Notion has a 100-block-per-request cap; this splits into chunks.
md_to_blocks() {
  # stdin: markdown
  # stdout: JSON array of Notion blocks
  python3 - "$@" <<'PYEOF'
import json, re, sys
md = sys.stdin.read()
blocks = []
in_code = False
code_lang = "plain text"
code_buf = []

def rtext(s):
    # Notion rich_text from a plain string (keeps markdown-like tokens literal).
    # Max 2000 chars per segment.
    out = []
    while s:
        chunk, s = s[:2000], s[2000:]
        out.append({"type": "text", "text": {"content": chunk}})
    return out

def flush_code():
    global code_buf, code_lang, in_code
    if code_buf:
        blocks.append({
            "object": "block",
            "type": "code",
            "code": {
                "language": code_lang,
                "rich_text": rtext("\n".join(code_buf))
            }
        })
    code_buf = []
    code_lang = "plain text"
    in_code = False

lines = md.splitlines()
i = 0
while i < len(lines):
    line = lines[i]
    if in_code:
        if line.startswith("```"):
            flush_code()
        else:
            code_buf.append(line)
        i += 1
        continue
    m = re.match(r"^```(\w*)\s*$", line)
    if m:
        in_code = True
        code_lang = m.group(1) or "plain text"
        # Notion supports a fixed language list; fall back
        if code_lang not in {"abap","arduino","bash","basic","c","clojure","coffeescript","c++","c#","css","dart","diff","docker","elixir","elm","erlang","flow","fortran","f#","gherkin","glsl","go","graphql","groovy","haskell","html","java","javascript","json","julia","kotlin","latex","less","lisp","livescript","lua","makefile","markdown","markup","matlab","mermaid","nix","objective-c","ocaml","pascal","perl","php","plain text","powershell","prolog","protobuf","python","r","reason","ruby","rust","sass","scala","scheme","scss","shell","solidity","sql","swift","typescript","vb.net","verilog","vhdl","visual basic","webassembly","xml","yaml"}:
            code_lang = "plain text"
        i += 1
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
        txt = re.sub(r"^\s*[-*]\s", "", line)
        blocks.append({"object":"block","type":"bulleted_list_item","bulleted_list_item":{"rich_text":rtext(txt)}})
    elif re.match(r"^\s*\d+\.\s", line):
        txt = re.sub(r"^\s*\d+\.\s", "", line)
        blocks.append({"object":"block","type":"numbered_list_item","numbered_list_item":{"rich_text":rtext(txt)}})
    elif line.strip() == "":
        pass  # skip blank lines
    else:
        blocks.append({"object":"block","type":"paragraph","paragraph":{"rich_text":rtext(line)}})
    i += 1
if in_code:
    flush_code()
# Notion API limits to 100 blocks per request; split and append later if needed.
# For now we return all — caller chunks when calling the append endpoint.
print(json.dumps(blocks))
PYEOF
}

append_blocks_chunked() {
  # $1 = page_id, stdin = blocks JSON array
  local page_id="$1"
  local blocks
  blocks="$(cat)"
  local total
  total="$(jq 'length' <<< "$blocks")"
  local i=0
  while (( i < total )); do
    local chunk
    chunk="$(jq ".[${i}:$((i+90))]" <<< "$blocks")"
    local body
    body="$(jq -n --argjson c "$chunk" '{children: $c}')"
    _api PATCH "/blocks/${page_id}/children" "$body" > /dev/null
    i=$((i+90))
  done
}

ensure_child_page() {
  # Find-or-create a child page by title under parent. $1=parent_id, $2=title
  # Returns: page_id on stdout
  local parent="$1" title="$2"
  local body search_res existing
  body="$(jq -n --arg q "$title" '{ query: $q, filter: { property: "object", value: "page" } }')"
  search_res="$(_api POST /search "$body" 2>/dev/null || echo '{}')"
  existing="$(jq -r --arg t "$title" --arg p "$parent" '
    .results // [] | map(select(.parent.page_id == $p and
      ((.properties.title.title // []) | map(.plain_text) | join("") == $t)
    )) | .[0].id // empty' <<< "$search_res")"
  if [[ -n "$existing" ]]; then
    echo "$existing"
    return 0
  fi
  local res
  res="$(create_page "$parent" "$title" '[]')"
  jq -r '.id' <<< "$res"
}

# ----- main flow -----

SLUG="$(basename "$REPORT_DIR")"
echo "push_to_notion: session=$SLUG" >&2

# 1. Ensure root "research-engine" page under the shared parent
ROOT_ID="${NOTION_ROOT_PAGE_ID:-}"
if [[ -z "$ROOT_ID" ]]; then
  ROOT_ID="$(ensure_child_page "$NOTION_PARENT_PAGE_ID" "research-engine")"
  echo "push_to_notion: root page id=$ROOT_ID (save as NOTION_ROOT_PAGE_ID to skip next time)" >&2
fi

# 2. Session page (main README.md content)
SESSION_ID="$(ensure_child_page "$ROOT_ID" "$SLUG")"
echo "push_to_notion: session page=$SESSION_ID" >&2

if [[ -f "$REPORT_DIR/README.md" ]]; then
  md_to_blocks < "$REPORT_DIR/README.md" | append_blocks_chunked "$SESSION_ID"
  echo "push_to_notion: wrote README.md blocks" >&2
fi

# 3. transcript subpage
if [[ -f "$REPORT_DIR/transcript.md" ]]; then
  TID="$(ensure_child_page "$SESSION_ID" "transcript")"
  md_to_blocks < "$REPORT_DIR/transcript.md" | append_blocks_chunked "$TID"
  echo "push_to_notion: wrote transcript" >&2
fi

# 4. session.md subpage (followup log)
if [[ -f "$REPORT_DIR/session.md" ]]; then
  SID="$(ensure_child_page "$SESSION_ID" "followups")"
  md_to_blocks < "$REPORT_DIR/session.md" | append_blocks_chunked "$SID"
  echo "push_to_notion: wrote followups" >&2
fi

# 5. related/ subpages
if [[ -d "$REPORT_DIR/related" ]]; then
  for f in "$REPORT_DIR/related"/*.md; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f" .md)"
    RID="$(ensure_child_page "$SESSION_ID" "$name")"
    md_to_blocks < "$f" | append_blocks_chunked "$RID"
  done
  echo "push_to_notion: wrote related/*" >&2
fi

# 6. Emit the session page URL
URL="$(_api GET "/pages/${SESSION_ID}" 2>/dev/null | jq -r '.url // empty')"
[[ -n "$URL" ]] || URL="https://www.notion.so/${SESSION_ID//-/}"
echo "$URL"
