#!/usr/bin/env bash
# zs build -g: gdb breaks on a Z# function, shows arguments and locals, steps through Z# lines,
# prints a backtrace with Z# files and lines, and shows a string, a record and a union as values.
# Addresses are left out of the output, and each command's variables are in name order: the order
# gdb lists a frame's locals in, across its nested blocks, isn't the same on every machine (arm64's
# lists the loop's sq after summary).
# gdb's commands from a file, not -ex arguments: a native Windows gdb started from Git Bash got
# "break square" split in two
zs=${1:-bin/zs}; dir=$(mktemp -d); exe=$dir/prog.exe
timeout 30 "$zs" build tests/debug/prog.zs -g -o "$exe" || exit 1
printf '%s\n' "break square" run bt "info args" next "print result" finish next "info locals" delete \
  "break prog.zs:22" continue "print name" "print range" "print summary" kill > "$dir/cmds"
# gdb's own output with GDB_RAW=1; else the lines checked: Windows' gdb says "Thread 1 hit
# Breakpoint 1", and a backtrace's frames are the Z# code's (below it, the C start-up's are the
# platform's: Linux's main, Windows' kernel32 and ntdll)
if [ -n "${GDB_RAW:-}" ]; then timeout 60 gdb -q -batch -x "$dir/cmds" "$exe" 2>&1; rm -rf "$dir"; exit; fi
timeout 60 gdb -q -batch -x "$dir/cmds" "$exe" 2>&1 | sed -E 's/^Thread [0-9]+ hit //' \
  | grep -E '^(Breakpoint|#|[a-z]+ = |[0-9]+\s|\$[0-9])' | sed -E '/^#/{/\.zs:/!d;}' \
  | sed -E 's/0x[0-9a-f]+/ADDR/g; s/ at ADDR: / /' \
  | LC_ALL=C awk '/^[a-z]+ = / { run[++n] = $0; next } { sorted(); print } END { sorted() }
      function sorted(  i, j, l) {
        for (i = 2; i <= n; i++) { l = run[i]; for (j = i - 1; j > 0 && run[j] > l; j--) run[j + 1] = run[j]; run[j + 1] = l }
        for (i = 1; i <= n; i++) print run[i]
        n = 0
      }'
rm -rf "$dir"
