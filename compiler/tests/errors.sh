#!/usr/bin/env bash
# The Z# compiler's zs build --strict on every test with an expected .err (its error lines, the
# source snippets under them left out, as ./test.sh compares them). Prints the tests that differ,
# with the first difference, and a count. Some .err files are errors of the passes after checking
# (what crosses threads, a SIMD feature): they come with those passes.
set -u
zs=${1:-compiler/build/zs}
total=0; bad=0
for e in $(find tests -name '*.err' | sort); do
  t=${e%.err}.zs
  [ -f "$t" ] || continue
  total=$((total + 1))
  got=$(timeout 30 "$zs" build --strict "$t" 2>&1 | grep -v '^ [ 0-9]* | ')
  want=$(cat "$e")
  if [ "$got" != "$want" ]; then
    bad=$((bad + 1))
    echo "$t: $(diff <(echo "$want") <(echo "$got") | grep '^[<>]' | head -2 | tr '\n' ' ')"
  fi
done
echo "$((total - bad)) of $total .err tests give the same errors"
