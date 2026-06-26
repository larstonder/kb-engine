#!/usr/bin/env bash
# kb-stale-sweep.sh - SessionStart hook: the KB janitor.
#
# Two jobs:
#   1. DEMOTE: verified entries whose verified_at is older than STALE_MONTHS
#      are set back to confidence: observed with verified_at cleared.
#   2. RECOMMEND-FOR-DELETION: entries that look dead are surfaced as a worklist.
#      The janitor NEVER deletes; deletion is human-gated.
#
# Deletion candidates: empty body, abandoned observed, or never consulted + stale.
# Structural category types (repos) are exempt from deletion candidates.
#
# Runs at most once per session via a TMPDIR marker. Always exits 0.
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$PROJ/.kbconfig" ] || exit 0
LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/lib"
. "$LIB/config.sh"; . "$LIB/gitops.sh"
kb_load_config || exit 0

# Dedup per session.
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null || echo nosession)"
MARKER="${TMPDIR:-/tmp}/kb-stale-sweep-${SESSION_ID}"
[ -f "$MARKER" ] && exit 0
: > "$MARKER"

USAGE_LOG="$KB_DIR_ABS/.usage.log"

STALE_MONTHS="$(kb_stale_months)"
ABANDON_MONTHS=$((STALE_MONTHS * 2))

# Cutoff epochs. Try BSD date (macOS), then GNU date (Linux). Bail if neither.
month_cutoff() {
  date -v-"$1"m +%s 2>/dev/null || date -d "$1 months ago" +%s 2>/dev/null || echo ""
}
CUTOFF_STALE="$(month_cutoff "$STALE_MONTHS")"
CUTOFF_ABANDON="$(month_cutoff "$ABANDON_MONTHS")"
{ [ -z "$CUTOFF_STALE" ] || [ -z "$CUTOFF_ABANDON" ]; } && exit 0

# Parse DD.MM.YYYY into an epoch. BSD form first, then GNU.
to_epoch() {
  local d="$1" day rest mon yr
  date -j -f "%d.%m.%Y" "$d" +%s 2>/dev/null && return 0
  day="${d%%.*}"; rest="${d#*.}"; mon="${rest%%.*}"; yr="${rest#*.}"
  date -d "${yr}-${mon}-${day}" +%s 2>/dev/null
}

trim() { printf '%s' "$1" | sed -e 's/^[[:space:]"'\'']*//' -e 's/[[:space:]"'\'']*$//'; }

field() { trim "$(grep -m1 "^$2:" "$1" 2>/dev/null | sed "s/^$2://")"; }

# Print "1" if the file has any non-whitespace content outside its frontmatter.
has_body() {
  awk '
    NR==1 && /^---[[:space:]]*$/ {infm=1; next}
    infm && /^---[[:space:]]*$/ {infm=0; next}
    infm {next}
    /[^[:space:]]/ {print "1"; exit}
  ' "$1"
}

consult_count() {
  [ -f "$USAGE_LOG" ] || { echo 0; return; }
  local n
  n="$(grep -cF -- " $1 " "$USAGE_LOG" 2>/dev/null)"
  echo "${n:-0}"
}

# Identify structural category types (exempt from deletion candidates).
REPOS_CATS="$(jq -r '.categories[] | select(.type=="repos") | .name' "$(kb_json)" 2>/dev/null | paste -sd'|' -)"

DEMOTED=()
CANDIDATES=()

while IFS= read -r cat; do
  [ -d "$KB_DIR_ABS/$cat" ] || continue
  for f in "$KB_DIR_ABS/$cat"/*.md; do
    [ -e "$f" ] || continue
    REL="${f#"$KB_DIR_ABS"/}"

    conf="$(field "$f" confidence)"
    vat="$(field "$f" verified_at)"
    upd="$(field "$f" updated)"

    # 1) Demote stale verified entries in place.
    if [ "$conf" = "verified" ] && [ -n "$vat" ]; then
      epoch="$(to_epoch "$vat")"
      case "$epoch" in '' | *[!0-9]*) : ;; *)
        if [ "$epoch" -lt "$CUTOFF_STALE" ]; then
          tmp="$(mktemp)"
          if sed -e 's/^confidence: verified.*/confidence: observed/' \
                 -e 's/^verified_at:.*/verified_at:/' \
                 "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f"; then
            DEMOTED+=("$REL (verified $vat)")
          else
            rm -f "$tmp"
          fi
          continue
        fi ;;
      esac
    fi

    # Structural categories are exempt from deletion candidates.
    if [ -n "$REPOS_CATS" ] && printf '%s\n' "$REPOS_CATS" | tr '|' '\n' | grep -qxF "$cat"; then
      continue
    fi

    # 2) Deletion candidates (recommend only).
    reason=""
    if [ -z "$(has_body "$f")" ]; then
      reason="empty body"
    elif [ "$conf" = "observed" ] && [ -z "$vat" ] && [ -n "$upd" ]; then
      ue="$(to_epoch "$upd")"
      case "$ue" in '' | *[!0-9]*) : ;; *)
        [ "$ue" -lt "$CUTOFF_ABANDON" ] && reason="abandoned observed (updated $upd, never verified)" ;;
      esac
    fi

    if [ -z "$reason" ]; then
      eff="$vat"; [ -z "$eff" ] && eff="$upd"
      ee="$(to_epoch "$eff")"
      case "$ee" in '' | *[!0-9]*) : ;; *)
        if [ "$ee" -lt "$CUTOFF_STALE" ] && [ "$(consult_count "$REL")" -eq 0 ]; then
          reason="never consulted and stale (effective date $eff)"
        fi ;;
      esac
    fi

    [ -n "$reason" ] && CANDIDATES+=("$REL - $reason")
  done
done < <(kb_categories)

[ "${#DEMOTED[@]}" -eq 0 ] && [ "${#CANDIDATES[@]}" -eq 0 ] && exit 0

if [ "${#DEMOTED[@]}" -gt 0 ]; then
  echo "[KB janitor] Demoted ${#DEMOTED[@]} stale verified entr$([ "${#DEMOTED[@]}" -eq 1 ] && echo y || echo ies) (verified_at older than ${STALE_MONTHS} months) back to observed:"
  for d in "${DEMOTED[@]}"; do echo "  - $d"; done
  echo "These are hypotheses again. When a task touches one, re-verify against current code per the read flow."
fi

if [ "${#CANDIDATES[@]}" -gt 0 ]; then
  echo "[KB janitor] ${#CANDIDATES[@]} entr$([ "${#CANDIDATES[@]}" -eq 1 ] && echo y || echo ies) look dead and may warrant deletion:"
  for c in "${CANDIDATES[@]}"; do echo "  - $c"; done
  echo "DO NOT delete automatically. Present these to the user and confirm each one individually; on a yes, delete that single file - only inside the KB dir - then move to the next. The user may keep any of them. Deletion is human-gated."
fi
exit 0
