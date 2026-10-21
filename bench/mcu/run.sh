#!/usr/bin/env bash
# MCU benchmarks: each program in Z# and in C, built for a Cortex-M chip with the same clang
# and the same runtime (runtime/rt-embedded.c), run bare-metal under QEMU with -icount (time
# advances per instruction, so counts are deterministic). Prints a Markdown table.
#   bench/mcu/run.sh [cortex-m4|cortex-m0plus] [-O2|-Os]
set -u
cd "$(dirname "$0")/../.."
mcu=${1:-cortex-m4}; opt=${2:--O2}
case $mcu in
  cortex-m4) zt=thumb-freestanding-eabihf; cpu=cortex_m4+vfp4d16sp; board=mps2-an386; heap=65536 ;;
  cortex-m0plus) zt=thumb-freestanding-eabi; cpu=cortex_m0plus; board=microbit; heap=8192 ;;
esac
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
sed "/INCLUDE cortex-m.ld/{r runtime/boards/cortex-m.ld
d}" "runtime/boards/$board.ld" > "$t/link.ld"
zs_opt=(); [ "$opt" = -Os ] && zs_opt=(-Os)

cbuild() { zig cc -target $zt -mcpu=$cpu $opt -ffunction-sections -fdata-sections -Wl,--gc-sections \
  -DZS_HEAP_SIZE=1024 -T "$t/link.ld" -I bench/mcu "$1" runtime/rt-embedded.c -o "$2" 2>&1; }
run() { timeout 120 qemu-system-arm -M $board -nographic -semihosting-config enable=on,target=native \
  -icount shift=0 -kernel "$1" 2>&1; }
field() { grep -o "$1=[0-9-]*" | head -1 | cut -d= -f2; }
size() { llvm-size "$1" | tail -1 | awk '{print $1 + $2, $2 + $3}'; } # flash (text+data), static RAM (data+bss)

cbuild bench/mcu/calib.c "$t/calib" >/dev/null || { echo "calibration doesn't build"; exit 1; }
ticks=$(run "$t/calib" | field ticks)
per=$(awk -v t="$ticks" 'BEGIN { printf "%.4f", 2000000 / t }') # instructions per tick

echo "**$mcu** ($board under QEMU, $opt; instructions = ticks × $per; Z# has a ${heap}-byte heap, C a 1024-byte one)"
echo
echo "| benchmark | result (Z# / C) | instructions Z# | instructions C | Z# / C | flash Z# | flash C | heap peak Z# | stack Z# | stack C |"
echo "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|"
for zs in bench/mcu/*.zs; do
  b=$(basename "$zs" .zs)
  if ! out=$(bin/zs build "$zs" --target $mcu "${zs_opt[@]}" -o "$t/$b-zs" 2>&1); then echo "| $b | Z# doesn't build: $(echo "$out" | head -1) |"; continue; fi
  cbuild "bench/mcu/$b.c" "$t/$b-c" >/dev/null || { echo "| $b | C doesn't build |"; continue; }
  rz=$(run "$t/$b-zs"); rc=$(run "$t/$b-c")
  read -r fz _ <<<"$(size "$t/$b-zs")"; read -r fc _ <<<"$(size "$t/$b-c")"
  iz=$(awk -v t="$(echo "$rz" | field ticks)" -v p="$per" 'BEGIN { printf "%.0f", t * p }')
  ic=$(awk -v t="$(echo "$rc" | field ticks)" -v p="$per" 'BEGIN { printf "%.0f", t * p }')
  ratio=$(awk -v a="$iz" -v b="$ic" 'BEGIN { printf "%.2f", a / b }')
  echo "| $b | $(echo "$rz" | field result) / $(echo "$rc" | field result) | $iz | $ic | $ratio | $fz | $fc | $(echo "$rz" | field heap_peak) | $(echo "$rz" | field stack) | $(echo "$rc" | field stack) |"
done
