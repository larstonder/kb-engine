#!/usr/bin/env bash
# log-consult.sh - append one consult line to $KB_DIR_ABS/.usage.log.
set -uo pipefail
PATH_REL="${1:-}"; RESULT="${2:-}"; TASK_ARG="${3:-}"
[ -n "$PATH_REL" ] && [ -n "$RESULT" ] || { echo "usage: log-consult.sh <rel> <result> [task]" >&2; exit 2; }
PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$PROJ/.kbconfig" ] || exit 0
LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}/lib"
. "$LIB/config.sh"
kb_load_config || exit 0
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TASK="${TASK_ARG:-${KB_TASK:-unknown}}"
echo "$TS $PATH_REL task=$TASK result=$RESULT" >> "$KB_DIR_ABS/.usage.log"
