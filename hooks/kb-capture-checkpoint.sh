#!/usr/bin/env bash
# kb-capture-checkpoint.sh - Stop hook: once per session, nudge a self-check for
# durable knowledge worth capturing. Fires at most once per session, and only
# when nothing has been captured yet (KB clean). Exit 2 + stderr blocks the stop
# once and feeds the reminder back to the model for a single self-review turn.
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$PROJ/.kbconfig" ] || exit 0
LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/lib"
. "$LIB/config.sh"; . "$LIB/gitops.sh"
kb_load_config || exit 0

# Avoid loops: if this stop was already triggered by a blocking hook, let it stop.
STOP_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)
[ "$STOP_ACTIVE" = "true" ] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo unknown)
MARKER="${TMPDIR:-/tmp}/claude-kb-checkpoint-${SESSION_ID}"
[ -f "$MARKER" ] && exit 0
: > "$MARKER"

# If the KB already has substantive uncommitted changes, knowledge was captured
# this session - skip the nudge. Exclude .usage.log (appended on every entry
# Read by kb-log-read.sh) and .obsidian/ (graph churn): both are tracked, so
# a bare `status --porcelain` is dirty after merely *reading* an entry, which
# would wrongly suppress the nudge for a session that captured nothing.
CHANGES=$(kb_git status --porcelain 2>/dev/null | grep -vE '(^.{2} )?(\.usage\.log|\.obsidian/)' || true)
if [ -n "$CHANGES" ]; then
  exit 0
fi

cat >&2 <<'MSG'
KB capture checkpoint: before ending, self-check - did you learn a durable gotcha,
convention, decision, glossary term, or recipe this session that a future session
would want? If yes, capture it now via the knowledge-base skill (announce-don't-ask;
do not ask permission). If nothing qualifies, just stop.
MSG
exit 2
