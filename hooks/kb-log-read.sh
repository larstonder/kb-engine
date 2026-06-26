#!/usr/bin/env bash
# kb-log-read.sh - PostToolUse(Read) hook: record a KB entry consult.
# Reads the hook JSON on stdin; if the file read is a KB entry under a
# configured category folder, appends one `result=read` line to .usage.log via
# log-consult.sh. De-dups per session so re-reading the same entry within one
# session counts as a single consult.
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$PROJ/.kbconfig" ] || exit 0
LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/lib"
. "$LIB/config.sh"; . "$LIB/gitops.sh"
kb_load_config || exit 0

FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -z "$FILE_PATH" ] && exit 0

# Match against the KB dir basename + any configured category.
KB_BASENAME="$(basename "$KB_DIR_ABS")"
CAT_ALT="$(kb_categories_alt)"
if ! printf '%s' "$FILE_PATH" | grep -qE "/$KB_BASENAME/(${CAT_ALT})/[^/]+\\.md\$"; then
  exit 0
fi

REL="${FILE_PATH##*/"$KB_BASENAME"/}"

SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null || echo nosession)"
SEEN_DIR="${TMPDIR:-/tmp}/kb-read-seen-${SESSION}"
mkdir -p "$SEEN_DIR" 2>/dev/null || true
MARKER="$SEEN_DIR/$(printf '%s' "$REL" | tr '/' '_')"
[ -e "$MARKER" ] && exit 0
: > "$MARKER"

LOG_CONSULT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/skills/knowledge-base/scripts/log-consult.sh"
bash "$LOG_CONSULT" "$REL" read "${KB_TASK:-auto-read}" 2>/dev/null || true
exit 0
