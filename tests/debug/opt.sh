#!/usr/bin/env bash
# zs build -g --release: the optimizer runs and the DWARF lines stay, so gdb breaks on a line of
# an optimized build and shows a backtrace with Z# files and lines (arguments may be optimized
# out, so only the frames and lines are checked). Addresses are left out of the output.
zs=${1:-bin/zs}; exe=$(mktemp)
timeout 30 "$zs" build tests/debug/opt.zs -g --release -o "$exe" || exit 1
timeout 30 gdb -q -batch -ex "break opt.zs:5" -ex run -ex bt -ex kill "$exe" 2>&1 \
  | grep -E '^(Breakpoint|#)' | sed -E 's/0x[0-9a-f]+/ADDR/g; s/ at ADDR: / /; s/\([^)]*\)/(…)/'
rm -f "$exe"
