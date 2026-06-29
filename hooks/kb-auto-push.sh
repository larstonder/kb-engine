#!/usr/bin/env bash
# kb-auto-push.sh - Stop hook: auto-commit and auto-push the KB.
#
# Resilience contract: one malformed entry must NOT strand the rest. If an entry
# fails KB validation, it is quarantined (unstaged, left in the working tree) and
# the clean remainder is still committed and pushed. The quarantined entry is then
# surfaced right here at Stop - after the push - by blocking the stop once so the
# agent fixes it in the moment, while it still has the context.
set -uo pipefail

# Stop hook payload (JSON on stdin). Read defensively so a manual run can't hang.
HOOK_INPUT=$(cat 2>/dev/null || true)
stop_active() { printf '%s' "$HOOK_INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; }

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$PROJ/.kbconfig" ] || exit 0
LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/lib"
. "$LIB/config.sh"; . "$LIB/gitops.sh"
kb_load_config || exit 0

ERR_LOG="$PROJ/.kb-push-errors.log"

log_err() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$ERR_LOG"
}

# Build the entry regex from configured categories (no hardcoded names).
ENTRY_RE="(^|/)($(kb_categories_alt))/.*\\.md\$"

# Weekly self-maintenance nudge: surface BACKLOG.md at the tail of a session.
BACKLOG_FILE="$KB_DIR_ABS/BACKLOG.md"
BACKLOG_STAMP="$KB_DIR_ABS/.backlog-surfaced"
BACKLOG_INTERVAL=604800 # 7 days, in seconds
backlog_due() {
  [ -f "$BACKLOG_FILE" ] || return 1
  local now last
  now=$(date +%s)
  last=$(cat "$BACKLOG_STAMP" 2>/dev/null || echo 0)
  case "$last" in *[!0-9]* | '') last=0 ;; esac
  [ "$last" -eq 0 ] || [ "$((now - last))" -ge "$BACKLOG_INTERVAL" ]
}

# Set when an entry is quarantined this run.
QUARANTINED=0
VALIDATION=""

# End-of-session prompts. Surface to the agent by blocking the stop once - guarded
# by stop_hook_active so a follow-up stop can't loop. Reached from every normal
# exit (including the no-work case, so the weekly nudge fires even when nothing was
# captured). Quarantine - actionable, this session's own work - wins over the nudge.
end_prompts_and_exit() {
  if ! stop_active; then
    if [ "$QUARANTINED" = "1" ]; then
      {
        echo "KB capture incomplete. You wrote KB entr(ies) that FAILED validation, so they were left UNCOMMITTED - the valid changes were already committed and pushed. Fix the entr(ies) below now, in this session; the next stop will commit them. Do NOT discard them."
        echo
        printf '%s\n' "$VALIDATION"
        echo
        echo "Rules in CONVENTIONS.md. Ghost-link: a [[link]] whose target file does not exist must be a BARE link with no surrounding prose, or you must create the target stub. Connectivity: an entry with a non-empty repos: must [[link]] at least one of those repos."
      } >&2
      exit 2
    fi
    if backlog_due; then
      date +%s > "$BACKLOG_STAMP" 2>/dev/null || true
      echo "KB self-maintenance (weekly): the knowledge-base backlog hasn't been reviewed in a while. Now that this task is wrapped up, skim BACKLOG.md and decide whether anything is ripe to act on - promote a deferred idea, propose or create a skill the KB has grown to need, prune stale notes, or record a gap you found. Optional: if nothing is ready, just continue. This KB is yours to evolve." >&2
      exit 2
    fi
  fi
  exit 0
}

# Run all enabled validators on a newline-separated list of KB-relative entry
# paths ($1) and echo their raw "FAIL: <path>:..." lines. The --root flag means
# we do NOT need to cd into the KB dir (unlike the reference).
validate_staged() {
  [ -z "${1:-}" ] && return 0
  printf '%s\n' "$1" | while IFS= read -r f; do
    [ -z "$f" ] && continue
    "$LIB/validate.sh" --root "$KB_DIR_ABS" "$KB_DIR_ABS/$f" 2>&1
    if [ "$(kb_check_enabled ghostLinks)" = "true" ]; then
      "$LIB/check-ghostlinks.sh" --root "$KB_DIR_ABS" "$KB_DIR_ABS/$f" 2>&1
    fi
    if [ "$(kb_check_enabled wikilinks)" = "true" ]; then
      "$LIB/check-wikilinks.sh" --root "$KB_DIR_ABS" "$KB_DIR_ABS/$f" 2>&1
    fi
    if [ "$(kb_check_enabled graphConnectivity)" = "true" ]; then
      "$LIB/check-graph.sh" --root "$KB_DIR_ABS" "$KB_DIR_ABS/$f" 2>&1
    fi
  done | grep '^FAIL:'
}

# Keep the error log bounded.
if [ -f "$ERR_LOG" ] && [ "$(wc -c <"$ERR_LOG" 2>/dev/null || echo 0)" -gt 262144 ]; then
  tail -n 200 "$ERR_LOG" > "$ERR_LOG.tmp" 2>/dev/null && mv "$ERR_LOG.tmp" "$ERR_LOG"
fi

# Precondition: KB dir must be a git repo (standalone/submodule), or part of one (inrepo).
if [ "$KB_MODE" != "inrepo" ] && [ ! -d "$KB_DIR_ABS/.git" ] && [ ! -f "$KB_DIR_ABS/.git" ]; then
  exit 0
fi
if [ "$KB_MODE" = "inrepo" ] && ! git -C "$KB_DIR_ABS" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# Parse `git status --porcelain -u -- .` output into two temp files.
# $1=prefix (from rev-parse --show-prefix), $2=entry regex, $3=commit-set file, $4=validate-set file.
# commit-set: all changed KB-relative paths (add/modify/delete/rename-old/rename-new).
# validate-set: only added/modified/rename-new category .md files (deletions/rename-old are NEVER validated).
# Uses character-index extraction (not awk $2) so paths containing spaces are preserved.
_parse_porcelain_paths() {
  local prefix="$1" entry_re="$2" commit_f="$3" validate_f="$4"
  : > "$commit_f"; : > "$validate_f"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local st pathpart
    st="${line:0:2}"
    pathpart="${line:3}"
    if printf '%s' "$st" | grep -qE '[RC]'; then
      # Rename/copy: "XY old -> new" — old side is gone, new side is the result.
      local old_path new_path
      old_path="${pathpart%% -> *}"; old_path="${old_path#"$prefix"}"
      new_path="${pathpart#* -> }";  new_path="${new_path#"$prefix"}"
      printf '%s\n' "$old_path" >> "$commit_f"
      printf '%s\n' "$new_path" >> "$commit_f"
      printf '%s' "$new_path" | grep -qE "$entry_re" && printf '%s\n' "$new_path" >> "$validate_f" || true
    elif printf '%s' "$st" | grep -q 'D'; then
      # never validate a deleted file
      local del_path="${pathpart#"$prefix"}"
      printf '%s\n' "$del_path" >> "$commit_f"
    else
      local chg_path="${pathpart#"$prefix"}"
      printf '%s\n' "$chg_path" >> "$commit_f"
      printf '%s' "$chg_path" | grep -qE "$entry_re" && printf '%s\n' "$chg_path" >> "$validate_f" || true
    fi
  done
}

# --- AUTO_COMMIT=false: validate only, never stage/commit/push (any mode) ---
if [ "$KB_AUTO_COMMIT" = "false" ]; then
  PREFIX=$(kb_git rev-parse --show-prefix 2>/dev/null)
  _COMMIT_F=$(mktemp); _VALIDATE_F=$(mktemp)
  kb_git status --porcelain -u -- . 2>/dev/null \
    | _parse_porcelain_paths "$PREFIX" "(^|/)($(kb_categories_alt))/.*\\.md\$" "$_COMMIT_F" "$_VALIDATE_F"
  ENTRIES=$(cat "$_VALIDATE_F")
  rm -f "$_COMMIT_F" "$_VALIDATE_F"
  if [ -n "$ENTRIES" ]; then
    VALIDATION=$(validate_staged "$ENTRIES")
    [ -n "$VALIDATION" ] && QUARANTINED=1
  fi
  end_prompts_and_exit
fi

# --- AUTO_COMMIT=true + inrepo: scoped commit, no push ---
if [ "$KB_MODE" = "inrepo" ]; then
  for marker in rebase-merge rebase-apply MERGE_HEAD; do
    if [ -e "$(kb_git rev-parse --git-path "$marker" 2>/dev/null)" ]; then
      log_err "inrepo: skipped (repo mid-operation: $marker)"; end_prompts_and_exit
    fi
  done
  PREFIX=$(kb_git rev-parse --show-prefix 2>/dev/null)
  _COMMIT_F=$(mktemp); _VALIDATE_F=$(mktemp)
  kb_git status --porcelain -u -- . 2>/dev/null \
    | _parse_porcelain_paths "$PREFIX" "(^|/)($(kb_categories_alt))/.*\\.md\$" "$_COMMIT_F" "$_VALIDATE_F"
  ALL=$(cat "$_COMMIT_F" | sed '/^$/d')
  ENTRIES=$(cat "$_VALIDATE_F")
  rm -f "$_COMMIT_F" "$_VALIDATE_F"
  [ -z "$ALL" ] && end_prompts_and_exit
  BAD=""
  if [ -n "$ENTRIES" ]; then
    VALIDATION=$(validate_staged "$ENTRIES")
    if [ -n "$VALIDATION" ]; then
      QUARANTINED=1
      # FAIL lines carry ABSOLUTE paths; strip "$KB_DIR_ABS/" back to KB-relative.
      BAD=$(printf '%s\n' "$VALIDATION" | sed -nE 's/^FAIL: ([^:]+):.*/\1/p' \
            | sed "s|^${KB_DIR_ABS}/||" | sort -u)
    fi
  fi
  GOOD=$(comm -23 <(printf '%s\n' "$ALL" | sort -u) <(printf '%s\n' "$BAD" | sed '/^$/d' | sort -u))
  if [ -n "$GOOD" ]; then
    # Stage each path individually: existing files are added normally; paths already
    # staged by the user (rename-old-sides from git mv) will fail `add` because the
    # file is gone, but the rename is already in the index so the commit still works.
    printf '%s\n' "$GOOD" | sed '/^$/d' | while IFS= read -r p; do
      kb_git add -- "$p" 2>>"$ERR_LOG" || true
    done
    # shellcheck disable=SC2046  # intentional word-split: path list must expand to separate args
    kb_git commit -m "Update KB" -- $(printf '%s\n' "$GOOD" | sed '/^$/d') 2>>"$ERR_LOG" \
      || log_err "inrepo scoped commit failed"
  fi
  end_prompts_and_exit
fi

# Detect work: uncommitted changes in the working tree, and/or stranded commits.
STATUS=$(kb_git_dirty)
AHEAD=$(kb_git_ahead)
if [ -z "$STATUS" ] && [ "$AHEAD" = "0" ]; then
  end_prompts_and_exit
fi

# Commit only when the working tree actually has changes. A clean tree with
# AHEAD>0 falls straight through to the push retry below.
if [ -n "$STATUS" ]; then
  if ! kb_git add -A 2>/dev/null; then
    log_err "git add failed"
    echo "[KB] auto-push: git add failed. See $ERR_LOG" >&2
    exit 0
  fi

  STAGED_ENTRIES=$(kb_git diff --cached --name-only 2>/dev/null | grep -E "$ENTRY_RE" || true)
  if [ -n "$STAGED_ENTRIES" ]; then
    VALIDATION=$(validate_staged "$STAGED_ENTRIES")
    if [ -n "$VALIDATION" ]; then
      BAD=$(printf '%s\n' "$VALIDATION" | sed -nE 's/^FAIL: ([^:]+):.*/\1/p' | sort -u)
      # Quarantine: unstage the offending entries (they stay in the working tree).
      printf '%s\n' "$BAD" | while IFS= read -r f; do
        [ -n "$f" ] && kb_git restore --staged -- "$f" 2>>"$ERR_LOG"
      done
      QUARANTINED=1
      log_err "quarantined failing entries (committing the rest): $(printf '%s\n' "$BAD" | paste -sd, -)"
    fi
  fi

  # Nothing left staged: skip the commit but still try to push any stranded commits.
  if kb_git diff --cached --quiet 2>/dev/null; then
    STATUS=""
  fi
fi

if [ -n "$STATUS" ]; then
  # Build a one-line commit message from what remains staged.
  STAGED=$(kb_git diff --cached --name-status 2>/dev/null)
  # shellcheck disable=SC2016
  ADDED=$(printf '%s\n' "$STAGED" | awk '$1 ~ /^A/ {print $2}' | grep -E "$ENTRY_RE" | sed -E 's|^[^/]+/||; s|\.md$||' | head -3 | paste -sd, -)
  # shellcheck disable=SC2016
  MODIFIED=$(printf '%s\n' "$STAGED" | awk '$1 ~ /^M/ {print $2}' | grep -E "$ENTRY_RE" | sed -E 's|^[^/]+/||; s|\.md$||' | head -3 | paste -sd, -)
  PARTS=""
  if [ -n "$ADDED" ]; then PARTS="Add $ADDED"; fi
  if [ -n "$MODIFIED" ]; then
    if [ -n "$PARTS" ]; then PARTS="$PARTS; update $MODIFIED"; else PARTS="Update $MODIFIED"; fi
  fi
  if [ -z "$PARTS" ]; then PARTS="Update KB"; fi

  if ! kb_git commit -m "$PARTS" 2>>"$ERR_LOG"; then
    log_err "commit rejected despite quarantine. Message was: $PARTS"
    echo "[KB] auto-push: commit rejected. See $ERR_LOG" >&2
    exit 0
  fi
fi

# Fetch before deciding whether a rebase is even needed.
# Failure is non-fatal: offline OR empty-remote bootstrap both mean "can't rebase yet".
kb_git_fetch 2>/dev/null || true

BEHIND=0
if kb_git rev-parse --verify -q "origin/$KB_BRANCH" >/dev/null 2>&1; then
  BEHIND=$(kb_git rev-list --count "HEAD..origin/$KB_BRANCH" 2>/dev/null || echo 0)
fi
if [ "$BEHIND" != "0" ]; then
  # Stash the working-tree residue so the rebase has a clean tree.
  STASHED=0
  if ! kb_git diff --quiet 2>/dev/null || [ -n "$(kb_git ls-files --others --exclude-standard 2>/dev/null)" ]; then
    kb_git stash push -u -m kb-auto-push-rebase 2>>"$ERR_LOG" && STASHED=1
  fi
  if ! kb_git rebase "origin/$KB_BRANCH" 2>>"$ERR_LOG"; then
    log_err "rebase failed; aborting and leaving commit local"
    kb_git rebase --abort 2>/dev/null || true
    [ "$STASHED" = 1 ] && kb_git stash pop 2>>"$ERR_LOG" || true
    echo "[KB] auto-push: rebase failed. Resolve manually next session." >&2
    exit 0
  fi
  if [ "$STASHED" = 1 ] && ! kb_git stash pop 2>>"$ERR_LOG"; then
    log_err "stash pop after rebase conflicted; quarantined entries left in stash"
    echo "[KB] auto-push: could not restore quarantined entries after rebase (in git stash). See $ERR_LOG" >&2
  fi
fi

if ! kb_git_push 2>>"$ERR_LOG"; then
  log_err "push failed (offline?); commit left local for next session"
  echo "[KB] auto-push: push failed. See $ERR_LOG. Will retry next session." >&2
  exit 0
fi

end_prompts_and_exit
