#!/usr/bin/env bash
# lib/check-graph.sh - reject entries orphaned from their repo node (repos hub).
set -uo pipefail
if [ "${1:-}" = "--root" ]; then shift 2; fi

EXIT=0

fail() {
  echo "FAIL: $1: $2" >&2
  EXIT=1
}

for f in "$@"; do
  # Only validate entries inside a category folder, and never repo entries
  # themselves (they would have to link to their own node).
  case "$f" in
    repos/*.md|*/repos/*.md) continue ;;
    glossary/*.md|conventions/*.md|decisions/*.md|recipes/*.md|gotchas/*.md) ;;
    */glossary/*.md|*/conventions/*.md|*/decisions/*.md|*/recipes/*.md|*/gotchas/*.md) ;;
    *) continue ;;
  esac

  [ -f "$f" ] || continue

  # Locate frontmatter (--- on line 1, closing --- later).
  [ "$(sed -n '1p' "$f")" = "---" ] || continue
  END=$(awk 'NR>1 && /^---$/ {print NR; exit}' "$f")
  [ -n "$END" ] || continue
  FM=$(sed -n "2,$((END-1))p" "$f")

  # Extract repo names from `repos:`, handling both inline and block YAML:
  #   repos: [a, b]
  #   repos:
  #     - a
  #     - b
  REPOS=$(echo "$FM" | awk '
    /^repos:/ {
      rest = $0; sub(/^repos:[ \t]*/, "", rest)
      if (rest ~ /\[/) {                       # inline form
        gsub(/[][,]/, " ", rest); print rest; next
      }
      block = 1; next                          # block form follows
    }
    block {
      if ($0 ~ /^[ \t]+-/) { item = $0; sub(/^[ \t]+-[ \t]*/, "", item); print item }
      else if ($0 ~ /^[^ \t]/) { block = 0 }   # next top-level key ends the list
    }
  ' | tr -d '"' | tr ' ' '\n' | sed '/^$/d')

  # No repos listed -> cross-cutting entry, exempt.
  [ -n "$REPOS" ] || continue

  # Pass if the file links at least one of the listed repos.
  linked=0
  while IFS= read -r repo; do
    [ -n "$repo" ] || continue
    if grep -qE "\[\[${repo}(\]\]|[#|])" "$f"; then linked=1; break; fi
  done <<< "$REPOS"

  if [ "$linked" -eq 0 ]; then
    fail "$f" "repos: is set but no [[wikilink]] to any listed repo ($(echo "$REPOS" | tr '\n' ' ')); add e.g. [[$(echo "$REPOS" | head -1)]] so the entry is connected in the graph"
  fi
done

exit "$EXIT"
