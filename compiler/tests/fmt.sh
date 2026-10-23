#!/usr/bin/env bash
# The Z# formatter against the F# one: `zs fmt --stdin` gives the same text (or the same failure)
# for every .zs file in the repository, and tests/fmt/reflow.in becomes tests/fmt/reflow.zs.
set -u
fs=${1:-bin/zs}; zs=${2:-compiler/build/zs}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
total=0; bad=0
for f in $(find tests lib examples packages compiler -name '*.zs' | sort) tests/fmt/reflow.in; do
  total=$((total + 1))
  "$fs" fmt --stdin < "$f" > "$t/a" 2>/dev/null; a=$?
  "$zs" fmt --stdin < "$f" > "$t/b" 2>/dev/null; b=$?
  if [ $a -ne $b ] || ! cmp -s "$t/a" "$t/b"; then
    bad=$((bad + 1))
    echo "$f: exit $a/$b: $(diff "$t/a" "$t/b" | head -4 | tr '\n' ' ')"
  fi
done
if ! diff <("$zs" fmt --stdin < tests/fmt/reflow.in 2>&1) tests/fmt/reflow.zs > /dev/null; then
  bad=$((bad + 1)); echo "tests/fmt/reflow: the Z# formatter's result differs"
fi
echo "$((total + 1 - bad)) of $((total + 1)) formatted the same"
