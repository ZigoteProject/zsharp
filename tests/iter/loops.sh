#!/usr/bin/env bash
# The cost of for over Iter (0017): a for over a Map is the loop Map.iter is (main's instructions
# the same, locals' names aside), and for over an array, a list and a string is one loop with the
# body in place: no closure and no allocation in the function.
set -u
zs=${1:-bin/zs}; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fn() { awk -v f="$2" '$0 ~ "^define" && index($0, "@\"zs." f "\"(") {p=1} p {print} p && /^}/ {p=0}' "$1"; }
# (no \b: BSD's sed, macOS's, has none)
norm() { sed -E 's/%slot\.[A-Za-z0-9_.$]*\.([0-9]+)([^A-Za-z0-9_]|$)/%slot.\1\2/g' | sort; }
"$zs" build tests/iter/map_for.zs -o "$t/a" --emit-llvm >/dev/null && "$zs" build tests/iter/map_iter.zs -o "$t/b" --emit-llvm >/dev/null || exit 1
if diff <(fn "$t/a.ll" main | norm) <(fn "$t/b.ll" main | norm) >/dev/null; then echo "for over a Map: Map.iter's loop"
else echo "for over a Map differs from Map.iter"; fi
"$zs" build tests/iter/loops.zs -o "$t/c" --emit-llvm >/dev/null || exit 1
for f in sumArray sumList 'count<int>'; do
  body=$(fn "$t/c.ll" "$f")
  if [ -z "$body" ]; then echo "$f: not found"
  elif echo "$body" | grep -q "zs_alloc\|zs_clo\|call i1 %"; then echo "$f: allocates or calls a closure"
  else echo "$f: one loop, nothing allocated"; fi
done
