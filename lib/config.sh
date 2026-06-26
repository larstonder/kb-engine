#!/usr/bin/env bash
# lib/config.sh - locate and load KB configuration. Source me.

export KB_SCHEMA_VERSION=1

kb_notice() { printf '[kb] %s\n' "$1" >&2; }

kb_project_dir() { printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}"; }

# Returns 1 if the project has no usable .kbconfig.
kb_load_config() {
  local proj cfg KB_DIR MODE BRANCH AUTO_COMMIT
  proj="$(kb_project_dir)"
  cfg="$proj/.kbconfig"
  [ -f "$cfg" ] || return 1
  KB_DIR=""; MODE="standalone"; BRANCH="main"; AUTO_COMMIT=""
  # shellcheck disable=SC1090
  . "$cfg"
  [ -n "${KB_DIR:-}" ] || return 1
  KB_PROJECT_DIR="$proj"
  case "$KB_DIR" in
    /*) KB_DIR_ABS="$KB_DIR" ;;
    *)  KB_DIR_ABS="$proj/$KB_DIR" ;;
  esac
  if [ -d "$KB_DIR_ABS" ]; then KB_DIR_ABS="$(cd "$KB_DIR_ABS" && pwd)"; fi
  KB_MODE="${MODE:-standalone}"
  KB_BRANCH="${BRANCH:-main}"
  if [ -z "${AUTO_COMMIT:-}" ]; then
    if [ "$KB_MODE" = "inrepo" ]; then AUTO_COMMIT="false"; else AUTO_COMMIT="true"; fi
  fi
  KB_AUTO_COMMIT="$AUTO_COMMIT"
  export KB_PROJECT_DIR KB_DIR_ABS KB_MODE KB_BRANCH KB_AUTO_COMMIT
}

kb_json() { printf '%s/kb.json' "$KB_DIR_ABS"; }
kb_categories()      { jq -r '.categories[].name' "$(kb_json)" 2>/dev/null; }
kb_category_types()  { jq -r '.categories[].type' "$(kb_json)" 2>/dev/null; }
kb_categories_alt()  { kb_categories | paste -sd'|' -; }
kb_check_enabled()   { jq -r --arg c "$1" '.checks[$c] // false' "$(kb_json)" 2>/dev/null; }
kb_stale_months()    { jq -r '.staleMonths // 3' "$(kb_json)" 2>/dev/null; }
kb_kbjson_version()  { jq -r '.version // 1' "$(kb_json)" 2>/dev/null; }
