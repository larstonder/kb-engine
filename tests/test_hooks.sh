#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
# No-KB project: every hook must no-op and exit 0.
empty="tests/.work/hk-empty"; rm -rf "$empty"; mkdir -p "$empty"
for h in kb-pull kb-stale-sweep kb-auto-push kb-log-read; do
  echo '{}' | env CLAUDE_PROJECT_DIR="$empty" bash "hooks/$h.sh" >/dev/null 2>&1
  assert_eq "0" "$?" "$h no-ops with no .kbconfig"
done
# capture-checkpoint also exits 0 when no KB.
echo '{}' | env CLAUDE_PROJECT_DIR="$empty" bash hooks/kb-capture-checkpoint.sh >/dev/null 2>&1
assert_eq "0" "$?" "kb-capture-checkpoint no-ops with no .kbconfig"
# log-consult appends a line.
work="tests/.work/hk"; rm -rf "$work"; mkdir -p "$work/glossary"
printf 'KB_DIR="."\nMODE="standalone"\nBRANCH="main"\n' > "$work/.kbconfig"
echo '{"version":1,"categories":[{"name":"glossary","type":"glossary"}],"checks":{}}' > "$work/kb.json"
CLAUDE_PROJECT_DIR="$work" bash skills/knowledge-base/scripts/log-consult.sh glossary/x.md read t
assert_file "$work/.usage.log"
assert_contains "$(cat "$work/.usage.log")" "glossary/x.md" "usage log records consult"

# kb-pull no-ops in inrepo (does not touch the main repo)
irp="tests/.work/pull-inrepo"; rm -rf "$irp"; mkdir -p "$irp/knowledge/glossary"
git -C "$irp" init -q
git -C "$irp" -c user.email=t@e -c user.name=t commit -q --allow-empty -m base
printf 'KB_DIR="knowledge"\nMODE="inrepo"\nAUTO_COMMIT="false"\nBRANCH="main"\n' > "$irp/.kbconfig"
echo '{"version":1,"categories":[{"name":"glossary","type":"glossary"}],"checks":{}}' > "$irp/knowledge/kb.json"
before="$(git -C "$irp" rev-parse HEAD)"
echo '{}' | CLAUDE_PROJECT_DIR="$irp" bash hooks/kb-pull.sh; rc=$?
assert_eq "0" "$rc" "kb-pull exits 0 in inrepo"
assert_eq "$before" "$(git -C "$irp" rev-parse HEAD)" "kb-pull did not change the main repo"

# version guard notice when kb.json version > engine
echo '{"version":99,"categories":[{"name":"glossary","type":"glossary"}],"checks":{}}' > "$irp/knowledge/kb.json"
out="$(echo '{}' | CLAUDE_PROJECT_DIR="$irp" bash hooks/kb-pull.sh 2>&1)"
assert_contains "$out" "v99" "kb-pull warns on newer kb.json version"

assert_summary
