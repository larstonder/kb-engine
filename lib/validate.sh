#!/usr/bin/env bash
# lib/validate.sh - config-driven frontmatter validator.
# Usage: validate.sh [--root <dir>] <file.md>...
set -uo pipefail

ROOT=""
if [ "${1:-}" = "--root" ]; then ROOT="$2"; shift 2; fi

find_root() {
  local f="$1" d
  d="$(cd "$(dirname "$f")" 2>/dev/null && pwd || echo "")"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/kb.json" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  return 1
}
[ -n "$ROOT" ] || ROOT="$(find_root "${1:-.}")" || { echo "FAIL: cannot locate kb.json" >&2; exit 1; }
KBJSON="$ROOT/kb.json"

ALLOWED_TYPES="$(jq -r '.categories[].type' "$KBJSON" 2>/dev/null | paste -sd' ' -)"
CAT_ALT="$(jq -r '.categories[].name' "$KBJSON" 2>/dev/null | paste -sd'|' -)"
ALLOWED_CONFIDENCE="observed verified"

EXIT=0
fail() { echo "FAIL: $1: $2" >&2; EXIT=1; }
in_set() { local v="$1"; shift; for s in "$@"; do [ "$v" = "$s" ] && return 0; done; return 1; }

YAML_PARSER=""
if command -v ruby >/dev/null 2>&1; then YAML_PARSER="ruby"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then YAML_PARSER="python3"; fi
yaml_valid() {
  case "$YAML_PARSER" in
    ruby)    ruby -ryaml -e 'begin; YAML.safe_load(STDIN.read); rescue => e; STDOUT.puts e.message.lines.first.to_s.strip; exit 1; end' ;;
    python3) python3 -c $'import sys, yaml\ntry:\n    yaml.safe_load(sys.stdin.read())\nexcept Exception as e:\n    print(str(e).splitlines()[0]); sys.exit(1)' ;;
  esac
}

for f in "$@"; do
  case "$f" in *.md) ;; *) continue ;; esac
  # Only validate files inside a configured category folder.
  base="${f#"$ROOT"/}"; cat="${base%%/*}"
  printf '%s\n' "$cat" | grep -qxE "$CAT_ALT" || continue
  [ -f "$f" ] || { fail "$f" "file does not exist"; continue; }

  [ "$(sed -n '1p' "$f")" = "---" ] || { fail "$f" "no frontmatter (first line not '---')"; continue; }
  END=$(awk 'NR>1 && /^---$/ {print NR; exit}' "$f")
  [ -n "$END" ] || { fail "$f" "frontmatter not closed"; continue; }
  FM=$(sed -n "2,$((END-1))p" "$f")

  if [ -n "$YAML_PARSER" ]; then
    YERR=$(printf '%s\n' "$FM" | yaml_valid) || fail "$f" "invalid YAML frontmatter: $YERR (quote '#' tags)"
  elif printf '%s\n' "$FM" | grep -Eq '^[a-z_]+:[[:space:]]*\[[^]]*[[:space:]]#'; then
    fail "$f" "unquoted '#' inside a YAML flow array (quote it)"
  fi

  get() { echo "$FM" | grep -E "^$1:" | head -1 | sed -E "s/^$1:[[:space:]]*//"; }
  TYPE=$(get type); TITLE=$(get title); CONFIDENCE=$(get confidence)
  CREATED=$(get created); UPDATED=$(get updated)

  [ -n "$TYPE" ] || fail "$f" "missing 'type'"
  if [ -n "$TYPE" ] && ! in_set "$TYPE" $ALLOWED_TYPES; then fail "$f" "type '$TYPE' not in allowed set: $ALLOWED_TYPES"; fi
  [ -n "$TITLE" ] || fail "$f" "missing 'title'"
  [ -n "$CONFIDENCE" ] || fail "$f" "missing 'confidence'"
  if [ -n "$CONFIDENCE" ] && ! in_set "$CONFIDENCE" $ALLOWED_CONFIDENCE; then fail "$f" "confidence '$CONFIDENCE' not in: $ALLOWED_CONFIDENCE"; fi
  [ -n "$CREATED" ] || fail "$f" "missing 'created'"
  [ -n "$UPDATED" ] || fail "$f" "missing 'updated'"

  # Per-category extraFields (generic; replaces the hardcoded type case block).
  while IFS=$'\t' read -r fname allowed; do
    [ -n "$fname" ] || continue
    val=$(get "$fname")
    if [ -z "$val" ]; then fail "$f" "$TYPE entry missing '$fname'"; continue; fi
    if [ -n "$allowed" ] && ! in_set "$val" $allowed; then fail "$f" "$fname '$val' not in allowed set: $allowed"; fi
  done < <(jq -r --arg t "$TYPE" '
      .categories[] | select(.type==$t) | (.extraFields // [])[]
      | [.name, ((.allowed // []) | join(" "))] | @tsv' "$KBJSON" 2>/dev/null)

  if [ "$CONFIDENCE" = "verified" ] && [ -z "$(get verified_at)" ]; then
    fail "$f" "confidence is 'verified' but verified_at is empty"
  fi
done
exit $EXIT
