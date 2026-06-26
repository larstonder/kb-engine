#!/usr/bin/env bash
# lib/check-wikilinks.sh - reject markdown-style internal links between entries.
set -uo pipefail
ROOT=""; if [ "${1:-}" = "--root" ]; then ROOT="$2"; shift 2; fi
[ -n "$ROOT" ] || ROOT="$PWD"
CATS="$(jq -r '.categories[].name' "$ROOT/kb.json" 2>/dev/null | paste -sd'|' -)"
[ -n "$CATS" ] || exit 0
EXIT=0
for f in "$@"; do
  case "$f" in *.md) ;; *) continue ;; esac
  case "$f" in INDEX.md|*/INDEX.md) continue ;; esac
  [ -f "$f" ] || continue
  hits=$(grep -nE "\]\(($CATS)/[^)]+\.md\)" "$f" || true)
  if [ -n "$hits" ]; then while IFS= read -r l; do echo "FAIL: $f:$l" >&2; done <<< "$hits"; EXIT=1; fi
done
exit $EXIT
