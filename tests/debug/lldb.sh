#!/usr/bin/env bash
# zs build -g under lldb, the debugger on macOS: what tests/debug/gdb.sh checks with gdb. lldb
# breaks on a Z# function, shows its arguments and locals, steps through Z# lines, prints a
# backtrace with Z# files and lines, and shows a string, a record and a union as values. Its types
# are C's (lldb reads DWARF through clang: a 64-bit int is a long, an f64 a double). Addresses
# are left out of the output.
zs=${1:-bin/zs}; dir=$(mktemp -d); exe="$dir/prog"
timeout 30 "$zs" build tests/debug/prog.zs -g -o "$exe" || exit 1
timeout 60 lldb -b -o "breakpoint set -n square" -o run -o bt -o "frame variable" -o next \
  -o "frame variable result" -o finish -o next -o "frame variable" -o "breakpoint delete 1" \
  -o "breakpoint set -f prog.zs -l 22" -o continue -o "frame variable name range summary" -o kill \
  -- "$exe" 2>&1 \
  | grep -E '^ *(\* )?frame #[01]:|^-> |^\([A-Za-z_ *]+\) [a-z]+ = ' \
  | sed -E 's/0x[0-9a-f]+/ADDR/g; s/^ *\* *//; s/^ +//'
rm -rf "$dir"
