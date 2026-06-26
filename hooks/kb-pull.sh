#!/usr/bin/env bash
# kb-pull.sh - SessionStart hook: fast-forward the KB to origin so a session
# starts from current knowledge. Non-destructive: never discards local commits
# or uncommitted changes. Always exits 0 so session start is never blocked.
set -uo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$PROJ/.kbconfig" ] || exit 0
LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/lib"
. "$LIB/config.sh"; . "$LIB/gitops.sh"
kb_load_config || exit 0

# Drop-in notices. SessionStart runs once per session, so these are once-per-session.
if ! command -v jq >/dev/null 2>&1; then
  kb_notice "jq not found on PATH - the knowledge base is inactive this session; install jq, then run /kb doctor"
else
  _kbver="$(kb_kbjson_version)"
  if [ "${_kbver:-1}" -gt "$KB_SCHEMA_VERSION" ] 2>/dev/null; then
    kb_notice "kb.json is v$_kbver but this engine speaks v$KB_SCHEMA_VERSION; update the kb-engine plugin or some checks may not apply"
  fi
fi

# inrepo: nothing to pull or fast-forward; never touch the parent repo.
[ "$KB_MODE" = "inrepo" ] && exit 0

ERR_LOG="$PROJ/.kb-push-errors.log"

log_err() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$ERR_LOG"
}

# Keep the error log bounded.
if [ -f "$ERR_LOG" ] && [ "$(wc -c <"$ERR_LOG" 2>/dev/null || echo 0)" -gt 262144 ]; then
  tail -n 200 "$ERR_LOG" > "$ERR_LOG.tmp" 2>/dev/null && mv "$ERR_LOG.tmp" "$ERR_LOG"
fi

# Precondition: KB dir must be a git repo.
if [ ! -d "$KB_DIR_ABS/.git" ] && [ ! -f "$KB_DIR_ABS/.git" ]; then
  exit 0
fi

# Refresh the remote ref. Offline / no network: skip silently.
if ! kb_git_fetch 2>/dev/null; then
  exit 0
fi

# Never touch a dirty tree: leave uncommitted work alone. The Stop hook owns
# validating, quarantining, committing, and pushing.
if [ -n "$(kb_git_dirty)" ]; then
  exit 0
fi

# Preserve local commits not yet on the remote. The Stop hook owns pushing them.
AHEAD="$(kb_git_ahead)"
if [ "$AHEAD" != "0" ]; then
  exit 0
fi

# Ensure we are on the right branch (a submodule may be in detached HEAD).
if ! kb_git_ensure_branch 2>>"$ERR_LOG"; then
  log_err "pull: ensure_branch failed"
  exit 0
fi

# Fast-forward only: advances to origin/$KB_BRANCH when behind, no-ops otherwise.
kb_git_pull_ff 2>/dev/null || true

exit 0
