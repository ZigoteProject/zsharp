#!/usr/bin/env bash
# Host benchmarks: each program in Z#, C (clang -O2, and with -ftrapv: overflow traps, as in
# Z#), Rust (-C opt-level=3), Swift (-O), Zig (ReleaseFast) and OCaml (ocamlopt), run
# natively. All must print the same as C. The first five are kernels (the Benchmarks Game and a
# red-black tree); the rest are small real programs, written in Z#, C and Rust (docs/reports/
# realworld.md). A language without a source for a program, or whose compiler isn't installed,
# shows "-".
# Time is the best of 3 runs at the full size, memory the peak RSS of those runs. Z#'s
# instructions are counted by valgrind (cachegrind) at a small size, which is deterministic
# and so can catch regressions.
#   bench/host/run.sh [names]            Markdown tables of times and peak memory
#   bench/host/run.sh --check [names]    Z# counts only; fails when a Z# program needs more than
#                                        5% over bench/host/baseline.txt
#   bench/host/run.sh --update [names]   Z# counts only, written to bench/host/baseline.txt (the
#                                        programs named, or all; the other lines are kept)
set -u
cd "$(dirname "$0")/../.."
mode=""; case ${1:-} in --check | --update) mode=$1; shift ;; esac
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# name, full size, counting size
benches=$(cat <<'LIST'
fib 42 24
binarytrees 18 10
nbody 20000000 10000
spectralnorm 4000 100
rbtree 1000000 20000
wordfreq 1000000 20000
json 200000 2000
interp 300000 3000
pathfind 2000 120
sha256 64 1
LIST
)
all=$benches
if [ $# -gt 0 ]; then
  for name in "$@"; do grep -q "^$name " <<< "$benches" || { echo "no benchmark $name"; exit 1; }; done
  benches=$(grep -E "^($(IFS='|'; echo "$*")) " <<< "$benches")
fi
langs="zs c ctrap rust swift zig ocaml"
ext() { case $1 in zs) echo zs ;; c | ctrap) echo c ;; rust) echo rs ;; swift) echo swift ;; zig) echo zig ;; ocaml) echo ml ;; esac; }
tool() { case $1 in zs) echo bin/zs ;; c | ctrap) echo clang ;; rust) echo rustc ;; swift) echo swiftc ;; zig) echo zig ;; ocaml) echo ocamlopt ;; esac; }

# build <lang> <bench>: compile into $t/<bench>-<lang>; the other languages' sources are compiled
# from copies in $t so their compilers leave no files next to them
build() {
  local src=bench/host/$2 out=$t/$2-$1
  case $1 in
    zs) bin/zs build "$src.zs" -o "$out" --release ;;
    c) clang -O2 "$src.c" -o "$out" -lm ;;
    ctrap) clang -O2 -ftrapv "$src.c" -o "$out" -lm ;;
    rust) rustc --edition 2021 -C opt-level=3 "$t/$2.rs" -o "$out" ;;
    swift) swiftc -O "$t/$2.swift" -o "$out" -lm ;;
    zig) zig build-exe -O ReleaseFast --cache-dir "$t/zig-cache" "$t/$2.zig" -femit-bin="$out" ;;
    ocaml) ocamlopt $(ocamlopt -config-var flambda | grep -q true && echo -O3) "$t/$2.ml" -o "$out" ;;
  esac
}
count() { valgrind --tool=cachegrind --cache-sim=no --cachegrind-out-file=/dev/null "$@" 2>&1 >/dev/null |
  grep -o 'I *refs: *[0-9,]*' | grep -o '[0-9,]*$' | tr -d ,; }
# best <program> <size>: "seconds peak-KB", the lowest of 3 runs each
best() {
  local b="" r=""
  for _ in 1 2 3; do
    local s; s=$( { TIMEFORMAT=%R; time /usr/bin/time -f %M -o "$t/rss" "$@" >/dev/null; } 2>&1 )
    local k; k=$(cat "$t/rss")
    if [ -z "$b" ] || awk -v s="$s" -v b="$b" 'BEGIN { exit !(s < b) }'; then b=$s; fi
    if [ -z "$r" ] || [ "$k" -lt "$r" ]; then r=$k; fi
  done
  echo "$b $r"
}
ratio() { awk -v a="$1" -v b="$2" 'BEGIN { if (b > 0) printf "%.2f", a / b; else print "-" }'; }

if [ -z "$mode" ]; then
  cp bench/host/*.rs bench/host/*.swift bench/host/*.zig bench/host/*.ml "$t"
  for l in $langs; do
    command -v "$(tool "$l")" >/dev/null || echo "$(tool "$l") isn't installed: its column shows -" >&2
  done
  header="| benchmark | Z# | C | C -ftrapv | Rust | Swift | Zig | OCaml |"
  times="$header"$'\n'"|---|---:|---:|---:|---:|---:|---:|---:|"
  mems=$times
fi
fail=0
: > "$t/counts"
while read -r b full small; do
  if [ -n "$mode" ]; then
    if ! out=$(build zs "$b" 2>&1); then echo "$b: Z# doesn't build: $(echo "$out" | head -1)"; fail=1; continue; fi
    build c "$b" || { echo "$b: C doesn't build"; fail=1; continue; }
    if [ "$("$t/$b-zs" "$small")" != "$("$t/$b-c" "$small")" ]; then echo "$b: outputs differ"; fail=1; continue; fi
    iz=$(count "$t/$b-zs" "$small")
    echo "$b $iz" >> "$t/counts"
    if [ "$mode" = --check ]; then
      base=$(awk -v b="$b" '$1 == b { print $2 }' bench/host/baseline.txt 2>/dev/null)
      if [ -z "$base" ]; then echo "$b: no baseline ($iz instructions)"; fail=1
      elif awk -v n="$iz" -v o="$base" 'BEGIN { exit !(n > o * 1.05) }'; then
        echo "$b: $iz instructions, $(ratio "$iz" "$base")× the baseline $base"; fail=1
      fi
    fi
    continue
  fi
  build c "$b" || { echo "$b: C doesn't build"; fail=1; continue; }
  expected=$("$t/$b-c" "$small")
  trow="| $b |"; mrow="| $b |"
  read -r tc kc <<< "$(best "$t/$b-c" "$full")"
  for l in $langs; do
    if [ "$l" = c ]; then s=$tc k=$kc
    elif [ ! -f "bench/host/$b.$(ext "$l")" ] || ! command -v "$(tool "$l")" >/dev/null; then
      trow+=" - |"; mrow+=" - |"; continue
    elif ! out=$(build "$l" "$b" 2>&1); then
      echo "$b: $l doesn't build: $(echo "$out" | head -1)" >&2; fail=1; trow+=" no build |"; mrow+=" - |"; continue
    elif [ "$("$t/$b-$l" "$small")" != "$expected" ]; then
      echo "$b: $l prints something else" >&2; fail=1; trow+=" wrong output |"; mrow+=" - |"; continue
    else read -r s k <<< "$(best "$t/$b-$l" "$full")"
    fi
    trow+=" $s ($(ratio "$s" "$tc")×) |"
    mrow+=" $(awk -v k="$k" 'BEGIN { printf "%.1f", k / 1024 }') |"
  done
  times+=$'\n'"$trow"; mems+=$'\n'"$mrow"
done <<< "$benches"
if [ -z "$mode" ]; then
  echo "**Time, seconds** (best of 3; × C in parentheses)"; echo; echo "$times"; echo
  echo "**Peak memory, MB** (maximum resident set size)"; echo; echo "$mems"
fi
if [ "$mode" = --update ]; then
  # the counts measured replace their programs' lines; the others stay, in the list's order
  cat "$t/counts" bench/host/baseline.txt 2>/dev/null | awk '!seen[$1]++' > "$t/merged"
  while read -r b _; do grep "^$b " "$t/merged"; done <<< "$all" > bench/host/baseline.txt
  cat bench/host/baseline.txt
fi
exit $fail
