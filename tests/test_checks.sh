#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
work="tests/.work/chk"; rm -rf "$work"; mkdir -p "$work/glossary"
cat > "$work/kb.json" <<'JSON'
{ "version":1, "categories":[{"name":"glossary","type":"glossary"}], "checks":{} }
JSON
bad="$work/glossary/a.md"
printf 'See [link](glossary/b.md) here.\n' > "$bad"
out="$(bash lib/check-wikilinks.sh --root "$work" "$bad" 2>&1)"; rc=$?
assert_eq "1" "$rc" "markdown internal link rejected"
assert_contains "$out" "a.md" "names the offending file"
good="$work/glossary/c.md"
printf 'See [[b]] here.\n' > "$good"
bash lib/check-wikilinks.sh --root "$work" "$good"
assert_eq "0" "$?" "wikilink form accepted"

# --- check-graph.sh: custom-category entries must wikilink their repos ---
work2="tests/.work/chk-graph"; rm -rf "$work2"
mkdir -p "$work2/notes" "$work2/repos"
cat > "$work2/kb.json" <<'JSON'
{ "version":1, "categories":[{"name":"notes","type":"note"},{"name":"repos","type":"repo"}], "checks":{} }
JSON

# Entry under custom category with repos: set but NO wikilink -> must FAIL
missing_link="$work2/notes/no-link.md"
cat > "$missing_link" <<'ENTRY'
---
repos: [my-repo]
---
This entry has no wikilink to my-repo.
ENTRY
out2="$(bash lib/check-graph.sh --root "$work2" "$missing_link" 2>&1)"; rc2=$?
assert_eq "1" "$rc2" "custom-cat entry with repos: but no wikilink is rejected"
assert_contains "$out2" "no-link.md" "names the offending file"

# Same entry WITH a [[my-repo]] wikilink -> must PASS
has_link="$work2/notes/has-link.md"
cat > "$has_link" <<'ENTRY'
---
repos: [my-repo]
---
See [[my-repo]] for details.
ENTRY
bash lib/check-graph.sh --root "$work2" "$has_link"
assert_eq "0" "$?" "custom-cat entry with repos: AND wikilink is accepted"

# Entry inside the repo-type category -> exempt regardless of wikilinks
repo_entry="$work2/repos/my-repo.md"
cat > "$repo_entry" <<'ENTRY'
---
repos: [my-repo]
---
No self-link needed.
ENTRY
bash lib/check-graph.sh --root "$work2" "$repo_entry"
assert_eq "0" "$?" "repo-type category entries are exempt"

assert_summary
