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
git config user.email test@example.com; git config user.name test
printf -- '---\ntype: gotcha\ntitle: X\nconfidence: observed\ncreated: 01.01.2026\nupdated: 01.01.2026\nseverity: nope\n---\nB\n' > gotchas/bad.md
git add gotchas/bad.md
git -c user.email=test@example.com -c user.name=test commit -m "x" >/dev/null 2>&1; rc=$?
cd "$ENGINE"
assert_eq "1" "$rc" "pre-commit blocks invalid entry"
errlog_ignored="$(git -C "$work/.knowledge" check-ignore .kb-push-errors.log >/dev/null 2>&1 && echo yes || echo no)"
assert_eq "yes" "$errlog_ignored" "kb error log is gitignored in the content repo"
assert_exit 1 bash bin/kb init "$work/.bad" --preset general --mode bogus --project "$work/.badproj"

# inrepo init: no git init in the dir, no pre-commit, .kbconfig has inrepo + AUTO_COMMIT=false
ir="tests/.work/inrepo"; rm -rf "$ir"; mkdir -p "$ir"; git -C "$ir" init -q
bash bin/kb init "$ir/knowledge" --preset general --mode inrepo --project "$ir"
[ ! -e "$ir/knowledge/.git" ] && echo "ok: inrepo dir has no own .git" || echo "FAIL: inrepo dir got its own .git"
assert_eq "no" "$([ -e "$ir/knowledge/.git/hooks/pre-commit" ] && echo yes || echo no)" "inrepo installs no pre-commit"
assert_contains "$(cat "$ir/.kbconfig")" 'MODE="inrepo"' ".kbconfig mode inrepo"
assert_contains "$(cat "$ir/.kbconfig")" 'AUTO_COMMIT="false"' "inrepo AUTO_COMMIT defaults false"

# --auto-commit override
ir2="tests/.work/inrepo2"; rm -rf "$ir2"; mkdir -p "$ir2"; git -C "$ir2" init -q
bash bin/kb init "$ir2/knowledge" --mode inrepo --auto-commit --project "$ir2"
assert_contains "$(cat "$ir2/.kbconfig")" 'AUTO_COMMIT="true"' "--auto-commit flips to true"

# standalone .kbconfig gets AUTO_COMMIT=true line
sa="tests/.work/sa"; rm -rf "$sa"; mkdir -p "$sa"
bash bin/kb init "$sa/.knowledge" --preset general --project "$sa"
assert_contains "$(cat "$sa/.kbconfig")" 'AUTO_COMMIT="true"' "standalone AUTO_COMMIT=true"

# re-run safety: a hand-edited kb.json survives a second init; --force resets it
printf '{"version":1,"categories":[{"name":"custom","type":"custom"}],"checks":{}}' > "$sa/.knowledge/kb.json"
bash bin/kb init "$sa/.knowledge" --preset general --project "$sa"
assert_contains "$(cat "$sa/.knowledge/kb.json")" '"custom"' "re-run preserves existing kb.json"
bash bin/kb init "$sa/.knowledge" --preset general --force --project "$sa"
assert_eq "" "$(grep -o custom "$sa/.knowledge/kb.json" || true)" "--force resets kb.json to preset"

# kb help shows the full usage (commands + modes + flags)
help_out="$(bash bin/kb help 2>&1)"; assert_eq "0" "$?" "kb help exits 0"
assert_contains "$help_out" "kb init <dir>" "help lists init"
assert_contains "$help_out" "inrepo" "help documents inrepo mode"
assert_contains "$help_out" "--auto-commit" "help documents flags"
assert_contains "$help_out" "$(bash bin/kb --help 2>&1)" "--help matches help"
# kb init with no dir prints usage, does NOT crash with 'unbound variable'
ni_out="$(bash bin/kb init 2>&1)"; ni_rc=$?
assert_eq "" "$(printf '%s' "$ni_out" | grep -i 'unbound variable' || true)" "kb init (no dir) does not crash"
assert_contains "$ni_out" "usage: kb init <dir>" "kb init (no dir) prints usage"
# unknown command points at help
unk_out="$(bash bin/kb bogus 2>&1 || true)"; assert_contains "$unk_out" "kb help" "unknown command points to kb help"

assert_summary
