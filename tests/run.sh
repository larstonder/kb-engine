#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
rc=0
for t in tests/test_*.sh; do
  [ -e "$t" ] || continue
  printf '\n=== %s ===\n' "$t"
  bash "$t" || rc=1
done
if command -v shellcheck >/dev/null 2>&1; then
  printf '\n=== shellcheck ===\n'
  shopt -s nullglob
  targets=(lib/*.sh hooks/*.sh skills/knowledge-base/scripts/*.sh)
  for extra in bin/kb install.sh; do [ -f "$extra" ] && targets+=("$extra"); done
  shopt -u nullglob
  if [ ${#targets[@]} -gt 0 ]; then
    shellcheck -S warning "${targets[@]}" || rc=1
  fi
else
  printf '\n(shellcheck not installed; skipping lint)\n'
fi
exit $rc
