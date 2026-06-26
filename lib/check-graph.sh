#!/usr/bin/env bash
# lib/check-graph.sh - reject entries orphaned from their repo node (repos hub).
set -uo pipefail
ROOT=""; if [ "${1:-}" = "--root" ]; then ROOT="$2"; shift 2; fi
[ -n "$ROOT" ] || ROOT="$PWD"

CATS="$(jq -r '.categories[].name' "$ROOT/kb.json" 2>/dev/null | paste -sd'|' -)"
[ -n "$CATS" ] || exit 0

REPO_CAT="$(jq -r '.categories[] | select(.type=="repo") | .name' "$ROOT/kb.json" 2>/dev/null | head -1)"

EXIT=0

fail() {
  echo "FAIL: $1: $2" >&2
  EXIT=1
}

for f in "$@"; do
  # Only validate entries inside a configured category folder.
  matched=0
  case "$f" in *.md) ;; *) continue ;; esac
  IFS='|' read -ra CAT_NAMES <<< "$CATS"
  for cat in "${CAT_NAMES[@]}"; do
    case "$f" in
      "${cat}/"*.md|*"/${cat}/"*.md) matched=1; break ;;
    esac
  done
  [ "$matched" -eq 1 ] || continue

  # Exempt entries inside the repo-type category.
  if [ -n "$REPO_CAT" ]; then
    case "$f" in
      "${REPO_CAT}/"*.md|*"/${REPO_CAT}/"*.md) continue ;;
    esac
  fi

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
