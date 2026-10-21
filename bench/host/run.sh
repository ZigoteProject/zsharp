#!/usr/bin/env bash
# Host benchmarks: each program in Z# and in C (clang -O2), run natively. Both must print the
# same. Time is the best of 3 runs at the full size; instructions are counted by valgrind
# (cachegrind) at a small size, which is deterministic and so can catch regressions.
#   bench/host/run.sh            a Markdown table of times and instruction counts
#   bench/host/run.sh --check    counts only; fails when a Z# program needs more than 5% over
#                                bench/host/baseline.txt
#   bench/host/run.sh --update   counts only, written to bench/host/baseline.txt
set -u
cd "$(dirname "$0")/../.."
mode=${1:-}
unset ZS_LEAKCHECK # measured as programs run normally
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# name, full size, counting size
benches=$(cat <<'LIST'
fib 38 24
binarytrees 18 10
nbody 5000000 10000
spectralnorm 2500 100
rbtree 1000000 20000
LIST
)

count() { valgrind --tool=cachegrind --cache-sim=no --cachegrind-out-file=/dev/null "$@" 2>&1 >/dev/null |
  grep -o 'I *refs: *[0-9,]*' | grep -o '[0-9,]*$' | tr -d ,; }
best() {
  local b=""
  for _ in 1 2 3; do
    local s; s=$( { TIMEFORMAT=%R; time "$@" >/dev/null; } 2>&1 )
    if [ -z "$b" ] || awk -v s="$s" -v b="$b" 'BEGIN { exit !(s < b) }'; then b=$s; fi
  done
  echo "$b"
}
ratio() { awk -v a="$1" -v b="$2" 'BEGIN { if (b > 0) printf "%.2f", a / b; else print "-" }'; }

if [ -z "$mode" ]; then
  echo "| benchmark | output | time Z# (s) | time C (s) | Z# / C | instructions Z# | instructions C | Z# / C |"
  echo "|---|---|---:|---:|---:|---:|---:|---:|"
fi
fail=0
: > "$t/counts"
while read -r b full small; do
  if ! out=$(bin/zs build "bench/host/$b.zs" -o "$t/$b-zs" 2>&1); then echo "| $b | Z# doesn't build: $(echo "$out" | head -1) |"; fail=1; continue; fi
  clang -O2 "bench/host/$b.c" -o "$t/$b-c" -lm || { echo "| $b | C doesn't build |"; fail=1; continue; }
  if [ "$("$t/$b-zs" "$small")" != "$("$t/$b-c" "$small")" ]; then echo "| $b | outputs differ |"; fail=1; continue; fi
  iz=$(count "$t/$b-zs" "$small"); ic=$(count "$t/$b-c" "$small")
  echo "$b $iz" >> "$t/counts"
  case $mode in
    "")
      tz=$(best "$t/$b-zs" "$full"); tc=$(best "$t/$b-c" "$full")
      echo "| $b | same | $tz | $tc | $(ratio "$tz" "$tc") | $iz | $ic | $(ratio "$iz" "$ic") |" ;;
    --check)
      base=$(awk -v b="$b" '$1 == b { print $2 }' bench/host/baseline.txt 2>/dev/null)
      if [ -z "$base" ]; then echo "$b: no baseline ($iz instructions)"; fail=1
      elif awk -v n="$iz" -v o="$base" 'BEGIN { exit !(n > o * 1.05) }'; then
        echo "$b: $iz instructions, $(ratio "$iz" "$base")× the baseline $base"; fail=1
      fi ;;
  esac
done <<< "$benches"
[ "$mode" = --update ] && cp "$t/counts" bench/host/baseline.txt && cat bench/host/baseline.txt
exit $fail
