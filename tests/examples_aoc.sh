#!/usr/bin/env bash
# examples/aoc (track S's exit test): ten Advent of Code puzzles, each solved with only the
# prelude, Core and Std on the puzzle's example input, built and run; the answers are the
# puzzles' published ones for those inputs.
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
for f in examples/aoc/day*.zs; do
  name=$(basename "$f" .zs)
  "$zs" build "$f" -o "$t/$name" || exit 1
  echo "== $name ($(wc -l < "$f") lines)"
  "$t/$name"
done
