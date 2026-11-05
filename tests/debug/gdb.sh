#!/usr/bin/env bash
# zs build -g: gdb breaks on a Z# function, shows arguments and locals, steps through Z# lines,
# prints a backtrace with Z# files and lines, and shows a string, a record and a union as values.
# Addresses are left out of the output, and each command's variables are in name order: the order
# gdb lists a frame's locals in, across its nested blocks, isn't the same on every machine (arm64's
# lists the loop's sq after summary).
zs=${1:-bin/zs}; exe=$(mktemp)
timeout 30 "$zs" build tests/debug/prog.zs -g -o "$exe" || exit 1
timeout 30 gdb -q -batch -ex "break square" -ex run -ex bt -ex "info args" -ex next -ex "print result" \
  -ex finish -ex next -ex "info locals" -ex delete -ex "break prog.zs:22" -ex continue \
  -ex "print name" -ex "print range" -ex "print summary" -ex kill "$exe" 2>&1 \
  | grep -E '^(Breakpoint|#|[a-z]+ = |[0-9]+\s|\$[0-9])' | sed -E 's/0x[0-9a-f]+/ADDR/g; s/ at ADDR: / /' \
  | LC_ALL=C awk '/^[a-z]+ = / { run[++n] = $0; next } { sorted(); print } END { sorted() }
      function sorted(  i, j, l) {
        for (i = 2; i <= n; i++) { l = run[i]; for (j = i - 1; j > 0 && run[j] > l; j--) run[j + 1] = run[j]; run[j + 1] = l }
        for (i = 1; i <= n; i++) print run[i]
        n = 0
      }'
rm -f "$exe"
