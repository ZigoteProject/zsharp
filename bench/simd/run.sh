#!/usr/bin/env bash
# Phase 8's exit test: dot product, nbody and a blur in SIMD Z# (F32x8) against their C versions
# with AVX or NEON intrinsics, best of 3 runs each: on x86-64 (both for x86-64-v3: AVX2 and
# FMA), then the same sources cross-compiled for aarch64 and run under qemu-user. Each Z# time
# should be within 10% of C's. Run in ./dev from the repository's root.
set -e
cd "$(dirname "$0")/../.."
out=$(mktemp -d)
best() { # the best wall time of 3 runs in ms: best <command…>
  local b=999999
  for _ in 1 2 3; do
    local s=$(date +%s%N)
    timeout 300 "$@" > /dev/null
    local t=$(( ($(date +%s%N) - s) / 1000000 ))
    (( t < b )) && b=$t
  done
  echo $b
}
printf "%-8s %-8s %10s %10s %8s\n" target program "Z# (ms)" "C (ms)" "Z# / C"
for b in dot nbody blur; do
  bin/zs build bench/simd/$b.zs -o $out/$b --cpu=x86-64-v3 --release
  clang -O2 -march=x86-64-v3 bench/simd/$b.c -o $out/$b-c -lm
  awk -v b=$b -v z=$(best $out/$b) -v c=$(best $out/$b-c) 'BEGIN { printf "%-8s %-8s %10d %10d %8.3f\n", "x86-64", b, z, c, z / c }'
done
for b in dot nbody blur; do
  bin/zs build bench/simd/$b.zs -o $out/$b-arm --target aarch64-linux-musl --release
  zig cc -target aarch64-linux-musl -O2 bench/simd/$b.c -o $out/$b-arm-c -lm
  awk -v b=$b -v z=$(best qemu-aarch64 $out/$b-arm) -v c=$(best qemu-aarch64 $out/$b-arm-c) 'BEGIN { printf "%-8s %-8s %10d %10d %8.3f\n", "aarch64", b, z, c, z / c }'
done
rm -rf $out
