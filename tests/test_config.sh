#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
. lib/config.sh

work="tests/.work/cfg"; rm -rf "$work"; mkdir -p "$work/.knowledge"
printf 'KB_DIR=".knowledge"\nMODE="standalone"\nBRANCH="main"\n' > "$work/.kbconfig"
cat > "$work/.knowledge/kb.json" <<'JSON'
{ "version":1,
  "categories":[{"name":"glossary","type":"glossary"},{"name":"gotchas","type":"gotcha"}],
  "checks":{"frontmatter":true,"wikilinks":false},
  "staleMonths":5 }
JSON

CLAUDE_PROJECT_DIR="$work" kb_load_config
assert_eq "0" "$?" "kb_load_config succeeds with .kbconfig"
assert_contains "$KB_DIR_ABS" "/.work/cfg/.knowledge" "KB_DIR_ABS resolved absolute"
assert_eq "standalone" "$KB_MODE" "mode parsed"
assert_eq "glossary|gotchas" "$(kb_categories_alt)" "categories alternation"
assert_eq "true" "$(kb_check_enabled frontmatter)" "frontmatter check enabled"
assert_eq "false" "$(kb_check_enabled wikilinks)" "wikilinks check disabled"
assert_eq "false" "$(kb_check_enabled missingKey)" "absent check defaults false"
assert_eq "5" "$(kb_stale_months)" "staleMonths read"

empty="tests/.work/empty"; rm -rf "$empty"; mkdir -p "$empty"
assert_exit 1 env CLAUDE_PROJECT_DIR="$empty" bash -c '. lib/config.sh; kb_load_config'
assert_summary
