#!/usr/bin/env bash
# The Z# parser's AST against the F# one's (zs ast prints both the same way, places included)
# for every .zs file in the repository the F# parser takes. Prints the files that differ, with
# the first difference, and a count.
set -u
fs=${1:-bin/zs}; zs=${2:-compiler/build/zs}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
total=0; bad=0
for f in $(find tests lib examples packages compiler -name '*.zs' | sort); do
  "$fs" ast "$f" > "$t/a" 2>/dev/null || continue
  total=$((total + 1))
  "$zs" ast "$f" > "$t/b" 2>/dev/null
  if ! cmp -s "$t/a" "$t/b"; then
    bad=$((bad + 1))
    echo "$f: $(diff "$t/a" "$t/b" | head -4 | tr '\n' ' ')"
  fi
done
echo "$((total - bad)) of $total files have the same AST"
