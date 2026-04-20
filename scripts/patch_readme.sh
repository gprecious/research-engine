#!/usr/bin/env bash
# Replace the <!-- viz:begin --> ... <!-- viz:end --> block in README.md with the
# contents of <block_file>. If markers are absent, insert before "## Sources"
# section (or append to end if no such section). Idempotent.
#
# Usage: patch_readme.sh <readme.md> <block_file>
set -euo pipefail

readme="${1:-}"
block_file="${2:-}"

[[ -f "$readme" ]]     || { echo "patch_readme: README not found: $readme" >&2; exit 1; }
[[ -f "$block_file" ]] || { echo "patch_readme: block file not found: $block_file" >&2; exit 1; }

python3 - "$readme" "$block_file" <<'PY'
import io, sys, re, pathlib

readme_path = pathlib.Path(sys.argv[1])
block_path  = pathlib.Path(sys.argv[2])

text  = readme_path.read_text(encoding="utf-8")
block_body = block_path.read_text(encoding="utf-8").rstrip("\n")
wrapped = f"<!-- viz:begin -->\n{block_body}\n<!-- viz:end -->"

begin = "<!-- viz:begin -->"
end   = "<!-- viz:end -->"

if begin in text and end in text:
    # Replace marker-bounded block in place.
    pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end), re.DOTALL)
    new_text = pattern.sub(wrapped, text, count=1)
else:
    # Insert before "## Sources" line, else append to end.
    sources_re = re.compile(r"^## Sources\s*$", re.MULTILINE)
    m = sources_re.search(text)
    if m:
        insert_at = m.start()
        # Leave blank line buffer above and below.
        prefix = text[:insert_at].rstrip("\n") + "\n\n"
        suffix = "\n\n" + text[insert_at:]
        new_text = prefix + wrapped + suffix
    else:
        trimmed = text.rstrip("\n")
        new_text = trimmed + "\n\n" + wrapped + "\n"

# Only write if changed (keeps mtime stable for no-op reruns).
if new_text != text:
    readme_path.write_text(new_text, encoding="utf-8")
PY
