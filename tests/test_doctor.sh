#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ENGINE="$PWD"

# healthy standalone KB -> exit 0
w="tests/.work/doc"; rm -rf "$w"; mkdir -p "$w"
bash bin/kb init "$w/.knowledge" --preset general --project "$w" >/dev/null
bash bin/kb doctor --project "$w" >/dev/null 2>&1
assert_eq "0" "$?" "doctor exits 0 on a healthy KB"

# broken kb.json -> exit non-zero, reports fail
printf 'not json' > "$w/.knowledge/kb.json"
out="$(bash bin/kb doctor --project "$w" 2>&1)"; rc=$?
assert_eq "1" "$rc" "doctor exits non-zero on invalid kb.json"
assert_contains "$out" "fail" "doctor reports a fail line"

# jq missing -> still runs, reports jq fail (fakebin PATH without jq)
fb="tests/.work/fakebin"; rm -rf "$fb"; mkdir -p "$fb"
for t in git sed grep awk cat env dirname basename cut tr sort head tail paste date mkdir rm ls find chmod cp mv printf bash sh; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$fb/$t"
done
out="$(PATH="$ENGINE/$fb" bash bin/kb doctor --project "$w" 2>&1)"; rc=$?
assert_eq "1" "$rc" "doctor exits non-zero when jq missing"
assert_contains "$out" "jq" "doctor reports jq missing"
assert_summary
