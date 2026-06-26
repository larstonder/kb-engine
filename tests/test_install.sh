#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
proj="tests/.work/inst"; rm -rf "$proj"; mkdir -p "$proj"
bash install.sh --project "$proj"
assert_file "$proj/.claude/kb-engine/hooks/kb-pull.sh"
assert_file "$proj/.claude/skills/knowledge-base/SKILL.md"
assert_exit 0 jq -e '.hooks.SessionStart' "$proj/.claude/settings.json"
n1="$(jq '.hooks.SessionStart[0].hooks | length' "$proj/.claude/settings.json")"
bash install.sh --project "$proj"   # second run
n2="$(jq '.hooks.SessionStart[0].hooks | length' "$proj/.claude/settings.json")"
assert_eq "$n1" "$n2" "re-running install does not duplicate hooks"
assert_summary
