#!/usr/bin/env bash
# Phase 7's exit test: parallel mandelbrot and nbody on 1 thread and on 8 and 16 (the cores and
# the hardware threads), the best of 3 runs each, next to their C versions with pthreads (what
# the machine allows); then each under ThreadSanitizer, which must report nothing. Run in ./dev
# from the repository's root.
set -e
cd "$(dirname "$0")/../.."
out=$(mktemp -d)
best() { # the best wall time of 3 runs in ms: best <threads> <program> <n>
  local b=999999
  for _ in 1 2 3; do
    local s=$(date +%s%N)
    ZS_WORKERS=$1 timeout 120 "$2" "$3" "$1" > /dev/null
    local t=$(( ($(date +%s%N) - s) / 1000000 ))
    (( t < b )) && b=$t
  done
  echo $b
}
printf "%-14s %8s %8s %8s %7s %7s\n" program "1 (ms)" "8 (ms)" "16 (ms)" "x8" "x16"
for p in mandelbrot:8000 nbody:6000; do
  name=${p%:*}; n=${p#*:}
  bin/zs build bench/parallel/$name.zs -o $out/$name --release
  clang -O2 bench/parallel/$name.c -o $out/$name-c -lm
  for v in $name $name-c; do
    one=$(best 1 $out/$v $n); eight=$(best 8 $out/$v $n); sixteen=$(best 16 $out/$v $n)
    awk -v p=$v -v a=$one -v b=$eight -v c=$sixteen 'BEGIN { printf "%-14s %8d %8d %8d %7.2f %7.2f\n", p, a, b, c, a / b, a / c }'
  done
done
for name in mandelbrot nbody; do
  bin/zs build bench/parallel/$name.zs -o $out/$name-tsan --sanitize=thread --release
  timeout 300 $out/$name-tsan 600 > /dev/null 2> $out/tsan.log || { cat $out/tsan.log; exit 1; }
  if grep -q "ThreadSanitizer" $out/tsan.log; then cat $out/tsan.log; exit 1; fi
  echo "$name: ThreadSanitizer reports nothing"
done
rm -rf $out
