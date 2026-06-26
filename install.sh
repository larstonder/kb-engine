#!/usr/bin/env bash
# install.sh - install the KB engine into a project without the plugin system.
set -uo pipefail
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PWD"
while [ $# -gt 0 ]; do case "$1" in --project) PROJECT="$2"; shift 2;; *) shift;; esac; done

DEST="$PROJECT/.claude/kb-engine"
mkdir -p "$DEST"
cp -R "$ENGINE_DIR/hooks" "$ENGINE_DIR/lib" "$DEST/"
mkdir -p "$PROJECT/.claude/skills"
cp -R "$ENGINE_DIR/skills/knowledge-base" "$PROJECT/.claude/skills/"
cp -R "$ENGINE_DIR/skills" "$DEST/"   # keep log-consult resolvable under engine root too

SETTINGS="$PROJECT/.claude/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Idempotent merge: only add our block if our marker command is absent.
MARK='/.claude/kb-engine/hooks/kb-pull.sh'
if grep -qF "$MARK" "$SETTINGS"; then
  echo "install: hooks already present; skipping merge"
else
  HOOKS_FRAGMENT="$(cat <<'JSON'
{
  "SessionStart": [ { "matcher": "", "hooks": [
    { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/kb-engine/hooks/kb-pull.sh" },
    { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/kb-engine/hooks/kb-stale-sweep.sh" } ] } ],
  "Stop": [ { "matcher": "", "hooks": [
    { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/kb-engine/hooks/kb-capture-checkpoint.sh" },
    { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/kb-engine/hooks/kb-auto-push.sh" } ] } ],
  "PostToolUse": [ { "matcher": "Read", "hooks": [
    { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/kb-engine/hooks/kb-log-read.sh" } ] } ]
}
JSON
)"
  tmp="$SETTINGS.tmp"
  jq --argjson add "$HOOKS_FRAGMENT" '
    .hooks = (.hooks // {}) |
    reduce ($add | keys_unsorted[]) as $k (.; .hooks[$k] = ((.hooks[$k] // []) + $add[$k]))
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "install: merged hooks into $SETTINGS"
fi
