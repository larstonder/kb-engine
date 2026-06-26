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

# AUTO_COMMIT default-by-mode + schema version + notice
work2="tests/.work/cfg2"; rm -rf "$work2"; mkdir -p "$work2/.knowledge"
cat > "$work2/.knowledge/kb.json" <<'JSON'
{ "version": 1, "categories":[{"name":"glossary","type":"glossary"}], "checks":{} }
JSON

# inrepo -> AUTO_COMMIT defaults false
printf 'KB_DIR=".knowledge"\nMODE="inrepo"\n' > "$work2/.kbconfig"
CLAUDE_PROJECT_DIR="$work2" kb_load_config
assert_eq "false" "$KB_AUTO_COMMIT" "inrepo defaults AUTO_COMMIT=false"

# standalone -> AUTO_COMMIT defaults true
printf 'KB_DIR=".knowledge"\nMODE="standalone"\n' > "$work2/.kbconfig"
CLAUDE_PROJECT_DIR="$work2" kb_load_config
assert_eq "true" "$KB_AUTO_COMMIT" "standalone defaults AUTO_COMMIT=true"

# explicit AUTO_COMMIT honored
printf 'KB_DIR=".knowledge"\nMODE="standalone"\nAUTO_COMMIT="false"\n' > "$work2/.kbconfig"
CLAUDE_PROJECT_DIR="$work2" kb_load_config
assert_eq "false" "$KB_AUTO_COMMIT" "explicit AUTO_COMMIT=false honored"

assert_eq "1" "$KB_SCHEMA_VERSION" "schema version constant"
assert_eq "1" "$(kb_kbjson_version)" "kb_kbjson_version reads version"
assert_contains "$(kb_notice hello 2>&1)" "[kb] hello" "kb_notice prints to stderr"

assert_summary
