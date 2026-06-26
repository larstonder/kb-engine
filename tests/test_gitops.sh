#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
. lib/gitops.sh

work="tests/.work/git"; rm -rf "$work"; mkdir -p "$work"
KB_DIR_ABS="$work"; KB_MODE="standalone"; KB_BRANCH="main"
kb_git init -q
git -C "$work" config user.email t@t
git -C "$work" config user.name t
assert_eq "" "$(kb_git_dirty)" "clean tree -> empty dirty"
printf 'x\n' > "$work/a.txt"
assert_contains "$(kb_git_dirty)" "a.txt" "new file -> dirty shows it"
assert_eq "0" "$(kb_git_ahead)" "no upstream -> ahead 0"
assert_summary
