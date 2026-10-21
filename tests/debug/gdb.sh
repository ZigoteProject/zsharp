#!/usr/bin/env bash
# zs build -g: gdb breaks on a Z# function, shows arguments and locals, steps through Z# lines
# and prints a backtrace with Z# files and lines. Addresses are left out of the output.
zs=${1:-bin/zs}; exe=$(mktemp)
timeout 30 "$zs" build tests/debug/prog.zs -g -o "$exe" || exit 1
timeout 30 gdb -q -batch -ex "break square" -ex run -ex bt -ex "info args" -ex next -ex "print result" \
  -ex finish -ex next -ex "info locals" -ex kill "$exe" 2>&1 \
  | grep -E '^(Breakpoint|#|[a-z]+ = |[0-9]+\s|\$[0-9])' | sed -E 's/0x[0-9a-f]+/ADDR/g; s/ at ADDR: / /'
rm -f "$exe"
