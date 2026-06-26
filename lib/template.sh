#!/usr/bin/env bash
# lib/template.sh - print an entry skeleton for a category from kb.json.
set -uo pipefail
ROOT=""; if [ "${1:-}" = "--root" ]; then ROOT="$2"; shift 2; fi
CAT="${1:-}"
[ -n "$ROOT" ] && [ -n "$CAT" ] || { echo "usage: template.sh --root <dir> <category>" >&2; exit 2; }
KBJSON="$ROOT/kb.json"
TYPE="$(jq -r --arg c "$CAT" '.categories[]|select(.name==$c)|.type' "$KBJSON" 2>/dev/null)"
[ -n "$TYPE" ] && [ "$TYPE" != "null" ] || { echo "unknown category: $CAT" >&2; exit 1; }
TODAY="$(date +%d.%m.%Y)"
{
  echo "---"
  echo "type: $TYPE"
  echo "title: "
  echo "confidence: observed"
  echo "created: $TODAY"
  echo "updated: $TODAY"
  jq -r --arg c "$CAT" '.categories[]|select(.name==$c)|(.extraFields//[])[]
    | "\(.name): \((.allowed//[])[0] // "")"' "$KBJSON" 2>/dev/null
  echo "---"
  echo ""
}
