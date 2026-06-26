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
assert_summary
