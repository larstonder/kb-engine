#!/usr/bin/env bash
# Integration test: fresh standalone remote gets its first push (bootstrap fix).
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT

PROJ="$S/proj"
KB="$PROJ/.knowledge"
REMOTE="$S/remote.git"

# Install engine into temp project, init standalone KB.
mkdir -p "$PROJ"
bash install.sh --project "$PROJ" >/dev/null 2>&1
bash bin/kb init "$KB" --preset general --project "$PROJ" >/dev/null 2>&1

# Set git identity and ensure branch is named 'main'.
git -C "$KB" config user.email test@example.com
git -C "$KB" config user.name test
git -C "$KB" branch -m main 2>/dev/null || true

# Create a bare remote with NO branches yet and add it as origin.
git init --bare -q "$REMOTE"
git -C "$KB" remote add origin "$REMOTE"

# Run the Stop hook (empty-remote bootstrap scenario).
echo '{}' | CLAUDE_PROJECT_DIR="$PROJ" bash "$PROJ/.claude/kb-engine/hooks/kb-auto-push.sh" >/dev/null 2>&1 || true

# Assert the bare remote now has 'main' (first push succeeded).
git -C "$REMOTE" rev-parse --verify main >/dev/null 2>&1
assert_eq "0" "$?" "bootstrap: fresh remote has main branch after first push"

ENGINE="$PWD"
# --- inrepo AUTO_COMMIT=true: scoped commit, never the user's other work ---
m="tests/.work/ap-inrepo"; rm -rf "$m"; mkdir -p "$m"
bash bin/kb init "$m/knowledge" --preset general --mode inrepo --auto-commit --project "$m"
git -C "$m" init -q 2>/dev/null || true
git -C "$m" -c user.email=t@e -c user.name=t add -A
git -C "$m" -c user.email=t@e -c user.name=t commit -q -m base
# a valid entry, an invalid entry, and an unrelated user-staged file
printf -- '---\ntype: gotcha\ntitle: Good\nconfidence: observed\ncreated: 01.01.2026\nupdated: 01.01.2026\nseverity: high\n---\nB\n' > "$m/knowledge/gotchas/good.md"
printf -- '---\ntype: gotcha\ntitle: Bad\nconfidence: observed\ncreated: 01.01.2026\nupdated: 01.01.2026\nseverity: nope\n---\nB\n' > "$m/knowledge/gotchas/bad.md"
printf 'unrelated work\n' > "$m/app.txt"; git -C "$m" add app.txt
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e \
  bash -c 'echo "{}" | CLAUDE_PROJECT_DIR="'"$m"'" bash hooks/kb-auto-push.sh' >/dev/null 2>&1
committed="$(git -C "$m" show --name-only --format= HEAD)"
assert_contains "$committed" "knowledge/gotchas/good.md" "inrepo committed the valid entry"
assert_eq "" "$(printf '%s' "$committed" | grep 'bad.md' || true)" "inrepo did NOT commit the invalid entry"
assert_eq "" "$(printf '%s' "$committed" | grep 'app.txt' || true)" "inrepo did NOT commit the user's unrelated file"
assert_contains "$(git -C "$m" status --porcelain)" "app.txt" "user's app.txt still staged/uncommitted"
assert_contains "$(git -C "$m" status --porcelain)" "bad.md" "invalid entry left in working tree"

# --- AUTO_COMMIT=false: no commit at all, index untouched ---
n="tests/.work/ap-nocommit"; rm -rf "$n"; mkdir -p "$n"
bash bin/kb init "$n/knowledge" --preset general --mode inrepo --no-auto-commit --project "$n"
git -C "$n" init -q 2>/dev/null || true
git -C "$n" -c user.email=t@e -c user.name=t add -A
git -C "$n" -c user.email=t@e -c user.name=t commit -q -m base
printf -- '---\ntype: gotcha\ntitle: G\nconfidence: observed\ncreated: 01.01.2026\nupdated: 01.01.2026\nseverity: high\n---\nB\n' > "$n/knowledge/gotchas/g.md"
head_before="$(git -C "$n" rev-parse HEAD)"
echo '{}' | CLAUDE_PROJECT_DIR="$n" bash hooks/kb-auto-push.sh >/dev/null 2>&1
assert_eq "$head_before" "$(git -C "$n" rev-parse HEAD)" "AUTO_COMMIT=false makes no commit"
assert_contains "$(git -C "$n" status --porcelain -u)" "g.md" "AUTO_COMMIT=false leaves the entry uncommitted"

assert_summary
