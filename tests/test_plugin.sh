#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
assert_exit 0 jq -e '.name and .version' .claude-plugin/plugin.json
assert_exit 0 jq -e '.hooks.SessionStart and .hooks.Stop and .hooks.PostToolUse' hooks/hooks.json
assert_contains "$(cat hooks/hooks.json)" '${CLAUDE_PLUGIN_ROOT}' "hooks reference plugin root"
assert_exit 0 jq -e '.plugins[0].source' .claude-plugin/marketplace.json
assert_summary
