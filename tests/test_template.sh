#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
work="tests/.work/tpl"; rm -rf "$work"; mkdir -p "$work"
cat > "$work/kb.json" <<'JSON'
{ "version":1, "categories":[
  {"name":"gotchas","type":"gotcha","extraFields":[{"name":"severity","allowed":["low","medium","high"]}]}],
  "checks":{} }
JSON
out="$(bash lib/template.sh --root "$work" gotchas)"
assert_contains "$out" "type: gotcha" "type line present"
assert_contains "$out" "confidence: observed" "confidence observed"
assert_contains "$out" "severity: low" "extraField defaulted to first allowed"
# The generated skeleton must validate.
mkdir -p "$work/gotchas"; printf '%s\n' "$out" | sed 's/title:.*/title: T/' > "$work/gotchas/g.md"
bash lib/validate.sh --root "$work" "$work/gotchas/g.md"
assert_eq "0" "$?" "generated skeleton validates"
assert_exit 1 bash lib/template.sh --root "$work" nope
assert_summary
