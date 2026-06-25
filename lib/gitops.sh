#!/usr/bin/env bash
# lib/gitops.sh - mode-aware git helpers. Source me. Requires KB_DIR_ABS,
# KB_MODE (standalone|submodule), KB_BRANCH.

kb_git() { git -C "$KB_DIR_ABS" "$@"; }

kb_git_dirty() { kb_git status --porcelain 2>/dev/null; }

kb_git_ahead() {
  kb_git rev-list --count "origin/$KB_BRANCH..HEAD" 2>/dev/null || echo 0
}

kb_git_fetch() { kb_git fetch origin "$KB_BRANCH" 2>/dev/null; }

kb_git_ensure_branch() {
  [ "$KB_MODE" = "submodule" ] || return 0
  [ -z "$(kb_git_dirty)" ] || return 0
  [ "$(kb_git_ahead)" = "0" ] || return 0
  if [ "$(kb_git symbolic-ref -q --short HEAD 2>/dev/null)" != "$KB_BRANCH" ]; then
    kb_git checkout "$KB_BRANCH" 2>/dev/null || true
  fi
}

kb_git_pull_ff() {
  kb_git_ensure_branch
  kb_git merge --ff-only "origin/$KB_BRANCH" 2>/dev/null || true
}

kb_git_push() {
  if [ "$KB_MODE" = "submodule" ]; then
    kb_git push origin "HEAD:$KB_BRANCH"
  else
    kb_git push origin "$KB_BRANCH"
  fi
}
