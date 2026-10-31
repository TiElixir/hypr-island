#!/usr/bin/env bash
# Validates module manifests: built-in ones, docs/examples, and any you pass.
#   tests/manifest-test.sh [path/to/module-dir ...]
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v jq >/dev/null || { echo "jq is required"; exit 1; }
dirs=("$@")
if [ ${#dirs[@]} -eq 0 ]; then
  for d in "$ROOT"/quickshell/island/modules/*/ "$ROOT"/docs/examples/*/; do
    [ -f "${d}manifest.json" ] && dirs+=("${d%/}")
  done
fi
fail=0
for d in "${dirs[@]}"; do
  m="$d/manifest.json"
  errs=$(jq -r '
    def types: ["bool","int","real","string","enum","color","list"];
    [
      (if (.id // "" | test("^[a-z0-9_-]+$")) then empty else "id must match ^[a-z0-9_-]+$" end),
      (if (.name // "" | length) > 0 then empty else "missing name" end),
      (if ((.entry // "module.qml") | test("^[^/].*\\.qml$") and (contains("..") | not)) then empty else "entry must be a relative .qml path" end),
      (if has("priority") and (.priority | type) != "number" then "priority must be a number" else empty end),
      (if has("subscribe") and ((.subscribe | type) != "array") then "subscribe must be an array" else empty end),
      (if has("source") and ((.source.command | type) != "array" or (.source.command | length) == 0) then "source.command must be a non-empty array" else empty end),
      (if has("source") and (.source.mode // "stream") != "stream" and .source.mode != "poll" then "source.mode must be stream or poll" else empty end),
      ((.options // [])[] | . as $o |
        (if ($o.key // "" | test("^[A-Za-z][A-Za-z0-9]*$")) then empty else "option key must be alphanumeric: \($o.key)" end),
        (if (types | index($o.type)) then empty else "option \($o.key): unknown type \($o.type)" end),
        (if $o | has("default") then empty else "option \($o.key): missing default" end),
        (if ($o.type == "bool" and ($o.default | type) != "boolean") then "option \($o.key): default must be boolean" else empty end),
        (if (($o.type == "int" or $o.type == "real") and ($o.default | type) != "number") then "option \($o.key): default must be a number" else empty end),
        (if (($o.type == "int" or $o.type == "real") and ($o | has("min")) and ($o.default < $o.min)) then "option \($o.key): default below min" else empty end),
        (if (($o.type == "int" or $o.type == "real") and ($o | has("max")) and ($o.default > $o.max)) then "option \($o.key): default above max" else empty end),
        (if ($o.type == "list" and ($o.default | type) != "array") then "option \($o.key): default must be an array" else empty end),
        (if ($o.type == "enum" and (($o.choices // []) | length) == 0) then "option \($o.key): enum needs choices" else empty end)
      ),
      (((.options // []) | map(.key) | group_by(.) | map(select(length > 1)) | .[][0]) | "duplicate option key: \(.)")
    ] | .[]' "$m" 2>&1)
  entry=$(jq -r '.entry // "module.qml"' "$m" 2>/dev/null)
  [ -f "$d/$entry" ] || errs="$errs"$'\n'"entry file missing: $entry"
  if [ -n "$errs" ]; then echo "FAIL $d"; echo "$errs" | sed '/^$/d; s/^/     /'; fail=1; else echo "ok   $d"; fi
done
[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
