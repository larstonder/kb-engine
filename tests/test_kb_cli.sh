#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
ENGINE="$PWD"
. tests/lib.sh
work="tests/.work/cli"; rm -rf "$work"; mkdir -p "$work"
bash bin/kb init "$work/.knowledge" --preset general --project "$work"
assert_file "$work/.kbconfig"
assert_file "$work/.knowledge/kb.json"
assert_file "$work/.knowledge/.kb/bin/validate.sh"
assert_file "$work/.knowledge/.git/hooks/pre-commit"
[ -d "$work/.knowledge/glossary" ] && echo "ok: glossary dir" || echo "FAIL: glossary dir"
# Pre-commit actually rejects an invalid entry.
cd "$work/.knowledge"
git config user.email t@t; git config user.name t
printf -- '---\ntype: gotcha\ntitle: X\nconfidence: observed\ncreated: 01.01.2026\nupdated: 01.01.2026\nseverity: nope\n---\nB\n' > gotchas/bad.md
git add gotchas/bad.md
git commit -m "x" >/dev/null 2>&1; rc=$?
cd "$ENGINE"
assert_eq "1" "$rc" "pre-commit blocks invalid entry"
assert_summary
