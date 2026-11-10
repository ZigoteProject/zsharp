#!/usr/bin/env bash
# zs build -g under lldb, the debugger on macOS: what tests/debug/gdb.sh checks with gdb. lldb
# breaks on a Z# function, shows its arguments and locals, steps through Z# lines, prints a
# backtrace with Z# files and lines, and shows a string, a record and a union as values. Its types
# are C's (lldb reads DWARF through clang: a 64-bit int is a long, an f64 a double). Addresses
# are left out of the output, and each command's variables are in name order: the order lldb lists
# a frame's locals in, across its nested blocks, isn't the same on every machine.
zs=${1:-bin/zs}; dir=$(mktemp -d); exe="$dir/prog"
timeout 300 "$zs" build tests/debug/prog.zs -g -o "$exe" || exit 1
timeout 60 lldb -b -o "breakpoint set -n square" -o run -o bt -o "frame variable" -o next \
  -o "frame variable result" -o finish -o next -o "frame variable" -o "breakpoint delete 1" \
  -o "breakpoint set -f prog.zs -l 22" -o continue -o "frame variable name range summary" -o kill \
  -- "$exe" 2>&1 \
  | grep -E '^ *(\* )?frame #[01]:|^-> |^\([A-Za-z_ *]+\) [a-z]+ = ' \
  | sed -E 's/0x[0-9a-f]+/ADDR/g; s/^ *\* *//; s/^ +//' \
  | LC_ALL=C awk '/^\([A-Za-z_ *]+\) [a-z]+ = / { run[++n] = $0; next } { sorted(); print } END { sorted() }
      function name(l) { sub(/^\([^)]*\) /, "", l); return l }
      function sorted(  i, j, l) {
        for (i = 2; i <= n; i++) { l = run[i]; for (j = i - 1; j > 0 && name(run[j]) > name(l); j--) run[j + 1] = run[j]; run[j + 1] = l }
        for (i = 1; i <= n; i++) print run[i]
        n = 0
      }'
rm -rf "$dir"
