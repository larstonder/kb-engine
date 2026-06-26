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
git -C "$KB" config user.email t@t
git -C "$KB" config user.name t
git -C "$KB" branch -m main 2>/dev/null || true

# Create a bare remote with NO branches yet and add it as origin.
git init --bare -q "$REMOTE"
git -C "$KB" remote add origin "$REMOTE"

# Run the Stop hook (empty-remote bootstrap scenario).
echo '{}' | CLAUDE_PROJECT_DIR="$PROJ" bash "$PROJ/.claude/kb-engine/hooks/kb-auto-push.sh" >/dev/null 2>&1 || true

# Assert the bare remote now has 'main' (first push succeeded).
git -C "$REMOTE" rev-parse --verify main >/dev/null 2>&1
assert_eq "0" "$?" "bootstrap: fresh remote has main branch after first push"

assert_summary
