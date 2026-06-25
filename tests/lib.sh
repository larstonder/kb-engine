#!/usr/bin/env bash
# Minimal assert harness. Source me; call assert_*; finish with assert_summary.
set -uo pipefail
KB_T_PASS=0
KB_T_FAIL=0

_ok()   { KB_T_PASS=$((KB_T_PASS+1)); printf 'ok: %s\n' "$1"; }
_fail() { KB_T_FAIL=$((KB_T_FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }

assert_eq() { # expected actual msg
  if [ "$1" = "$2" ]; then _ok "$3"; else _fail "$3 (expected [$1] got [$2])"; fi
}
assert_contains() { # haystack needle msg
  case "$1" in *"$2"*) _ok "$3" ;; *) _fail "$3 (missing [$2])" ;; esac
}
assert_exit() { # expected_code cmd...
  local exp="$1"; shift
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$exp" ]; then _ok "exit $exp: $*"; else _fail "exit: $* (expected $exp got $got)"; fi
}
assert_file() { [ -f "$1" ] && _ok "file $1" || _fail "file missing $1"; }

assert_summary() {
  printf '\n%d passed, %d failed\n' "$KB_T_PASS" "$KB_T_FAIL"
  [ "$KB_T_FAIL" -eq 0 ]
}
