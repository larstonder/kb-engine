#!/usr/bin/env bash
# lib/check-ghostlinks.sh - reject paraphrased glosses next to ghost wikilinks.
set -uo pipefail
ROOT=""; if [ "${1:-}" = "--root" ]; then ROOT="$2"; shift 2; fi
[ -n "$ROOT" ] || ROOT="$PWD"
EXIT=0
INDEX=$(find "$ROOT" -type f -name '*.md' -not -path '*/.git/*' -exec basename {} .md \; | sort -u)
target_exists() { echo "$INDEX" | grep -qxF "$1"; }
for f in "$@"; do
  [ -f "$f" ] || continue
  case "$f" in *.md) ;; *) continue ;; esac
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    targets=$(echo "$line" | grep -oE '\[\[[^]]+\]\]' | sed -E 's/^\[\[//;s/\]\]$//' | sed -E 's/\|.*$//')
    [ -z "$targets" ] && continue
    stripped=$(echo "$line" | sed -E 's/\[\[[^]]+\]\]//g' | sed -E 's/^[[:space:]]*[-*>][[:space:]]*//')
    stripped=$(echo "$stripped" | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//')
    has_gloss=0; { [ -n "$stripped" ] && [ "${#stripped}" -gt 2 ]; } && has_gloss=1
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      if ! target_exists "$t" && [ $has_gloss -eq 1 ]; then
        echo "FAIL: $f:$lineno: ghost-link [[${t}]] with paraphrased gloss; target does not exist" >&2; EXIT=1
      fi
    done <<< "$targets"
  done < "$f"
done
exit $EXIT
