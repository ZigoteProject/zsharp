#!/usr/bin/env bash
# The Z# parser against the F# one over every .zs file in the repository: the same tree (zs tree
# prints it the same way in both) for a file that parses, and the same first error for one that
# doesn't (the F# parser stops there; the Z# one goes on). Prints the files that differ, with the
# first difference, and a count.
set -u
fs=${1:-bin/zs}; zs=${2:-compiler/build/zs}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
total=0; bad=0
for f in $(find tests lib examples packages compiler -name '*.zs' | sort); do
  total=$((total + 1))
  "$fs" tree "$f" > "$t/a" 2> "$t/ea"; a=$?
  "$zs" tree "$f" > "$t/b" 2> "$t/eb"; b=$?
  if [ $a -eq 0 ]; then
    if [ $b -ne 0 ] || ! cmp -s "$t/a" "$t/b"; then
      bad=$((bad + 1))
      echo "$f: $(diff "$t/a" "$t/b" | head -4 | tr '\n' ' ') $(head -1 "$t/eb")"
    fi
  else
    ma=$(grep -m1 -o 'error: .*' "$t/ea"); mb=$(grep -m1 -o 'error: .*' "$t/eb")
    if [ "$ma" != "$mb" ]; then
      bad=$((bad + 1))
      echo "$f: F#: $ma / Z#: $mb"
    fi
  fi
done
echo "$((total - bad)) of $total files parse the same"
