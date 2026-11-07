#!/usr/bin/env bash
# zs build -g --release: the optimizer runs and the DWARF lines stay, so gdb breaks on a line of
# an optimized build and shows a backtrace with Z# files and lines (arguments may be optimized
# out, so only the frames and lines are checked). Addresses are left out of the output.
# gdb's commands from a file, not -ex arguments: a native Windows gdb started from Git Bash got
# "break opt.zs:5" split in two
zs=${1:-bin/zs}; dir=$(mktemp -d); exe=$dir/opt.exe
timeout 30 "$zs" build tests/debug/opt.zs -g --release -o "$exe" || exit 1
printf '%s\n' "break opt.zs:5" run bt kill > "$dir/cmds"
# gdb's own output with GDB_RAW=1; else the lines checked: Windows' gdb says "Thread 1 hit
# Breakpoint 1", and a backtrace's frames are the Z# code's (below it, the C start-up's are the
# platform's: Linux's main, Windows' kernel32 and ntdll)
if [ -n "${GDB_RAW:-}" ]; then timeout 60 gdb -q -batch -x "$dir/cmds" "$exe" 2>&1; rm -rf "$dir"; exit; fi
timeout 60 gdb -q -batch -x "$dir/cmds" "$exe" 2>&1 | sed -E 's/^Thread [0-9]+ hit //' \
  | grep -E '^(Breakpoint|#)' | sed -E '/^#/{/\.zs:/!d;}' \
  | sed -E 's/0x[0-9a-f]+/ADDR/g; s/ at ADDR: / /; s/\([^)]*\)/(…)/'
rm -rf "$dir"
