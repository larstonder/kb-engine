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

# scoped commit: stages+commits only the named KB-relative path (even untracked),
# never the user's other staged work.
sc="tests/.work/git-scoped"; rm -rf "$sc"; mkdir -p "$sc/sub"
KB_DIR_ABS="$sc/sub"; KB_MODE="inrepo"; KB_BRANCH="main"
git -C "$sc" init -q
git -C "$sc" -c user.email=t@e -c user.name=t commit -q --allow-empty -m base
printf 'a\n' > "$sc/sub/a.md"        # untracked new KB file
printf 'b\n' > "$sc/other.txt"
git -C "$sc" -c user.email=t@e -c user.name=t add other.txt   # user's unrelated staged work
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e \
  kb_git_commit_scoped "kb" "a.md"
committed="$(git -C "$sc" show --name-only --format= HEAD)"
assert_contains "$committed" "sub/a.md" "scoped commit included a.md"
assert_eq "" "$(printf '%s' "$committed" | grep other.txt || true)" "scoped commit excluded other.txt"
assert_contains "$(git -C "$sc" status --porcelain)" "other.txt" "other.txt remains staged/uncommitted"

# inrepo push is a no-op (returns 0 even with no remote)
KB_MODE="inrepo"
assert_exit 0 kb_git_push

assert_summary
