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
assert_eq "yes" "$([ -d "$work/.knowledge/glossary" ] && echo yes || echo no)" "glossary dir exists"
# Pre-commit actually rejects an invalid entry.
cd "$work/.knowledge"
git config user.email t@t; git config user.name t
printf -- '---\ntype: gotcha\ntitle: X\nconfidence: observed\ncreated: 01.01.2026\nupdated: 01.01.2026\nseverity: nope\n---\nB\n' > gotchas/bad.md
git add gotchas/bad.md
git commit -m "x" >/dev/null 2>&1; rc=$?
cd "$ENGINE"
assert_eq "1" "$rc" "pre-commit blocks invalid entry"
errlog_ignored="$(git -C "$work/.knowledge" check-ignore .kb-push-errors.log >/dev/null 2>&1 && echo yes || echo no)"
assert_eq "yes" "$errlog_ignored" "kb error log is gitignored in the content repo"
assert_exit 1 bash bin/kb init "$work/.bad" --preset general --mode bogus --project "$work/.badproj"
assert_summary
