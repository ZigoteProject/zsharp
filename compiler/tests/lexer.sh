#!/usr/bin/env bash
# The Z# lexer against the F# one: the same tokens (offset, length, text or layout) for every .zs
# file in the repository. Prints the files that differ, with the first difference, and a count.
set -u
fs=${1:-bin/zs}; zs=${2:-compiler/build/zs}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
total=0; bad=0
for f in $(find tests lib examples packages compiler -name '*.zs' | sort); do
  total=$((total + 1))
  "$fs" tokens "$f" > "$t/a" 2>/dev/null
  "$zs" tokens "$f" > "$t/b" 2>/dev/null
  if ! cmp -s "$t/a" "$t/b"; then
    bad=$((bad + 1))
    echo "$f: $(diff "$t/a" "$t/b" | head -3 | tr '\n' ' ')"
  fi
done
echo "$((total - bad)) of $total files lex the same"
