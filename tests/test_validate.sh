#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
work="tests/.work/val"; rm -rf "$work"; mkdir -p "$work/gotchas"
cat > "$work/kb.json" <<'JSON'
{ "version":1,
  "categories":[
    {"name":"gotchas","type":"gotcha",
     "extraFields":[{"name":"severity","allowed":["low","medium","high"]}]}],
  "checks":{"frontmatter":true} }
JSON

good="$work/gotchas/ok.md"
cat > "$good" <<'MD'
---
type: gotcha
title: Example
confidence: observed
created: 01.01.2026
updated: 01.01.2026
severity: high
---
Body.
MD
bash lib/validate.sh --root "$work" "$good"
assert_eq "0" "$?" "valid entry passes"

bad="$work/gotchas/bad.md"
cat > "$bad" <<'MD'
---
type: gotcha
title: Bad
confidence: observed
created: 01.01.2026
updated: 01.01.2026
severity: extreme
---
Body.
MD
out="$(bash lib/validate.sh --root "$work" "$bad" 2>&1)"; rc=$?
assert_eq "1" "$rc" "bad severity fails"
assert_contains "$out" "severity" "failure names severity"

notype="$work/gotchas/nt.md"
printf -- '---\ntitle: X\nconfidence: observed\ncreated: 01.01.2026\nupdated: 01.01.2026\nseverity: low\n---\nB\n' > "$notype"
out="$(bash lib/validate.sh --root "$work" "$notype" 2>&1)"
assert_contains "$out" "missing 'type'" "missing type reported"
assert_summary
