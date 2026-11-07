#!/usr/bin/env bash
# zs build -g: gdb shows heap values through their objects: a list's cell (count, head, tail) and
# the next, an array's count, length and elements, a tree's node with its fields, a tagged
# union's cell's case and that case's fields (the other cases' lie over the same bytes), an
# option over a string as the string, a ref's value. Addresses are left out of the output.
# gdb's commands from a file, not -ex arguments: a native Windows gdb started from Git Bash got
# "break square" split in two
zs=${1:-bin/zs}; dir=$(mktemp -d); exe=$dir/heap.exe
timeout 30 "$zs" build tests/debug/heap.zs -g -o "$exe" || exit 1
printf '%s\n' "break heap.zs:18" run "print *xs" "print *xs->tail" "print xs->tail->tail->tail" "print *names" \
  "print *names->elements[1]" "print *tree" "print token->case" "print token->Word" "print *some" "print *cell" \
  "whatis xs" "whatis tree" kill > "$dir/cmds"
if [ -n "${GDB_RAW:-}" ]; then timeout 60 gdb -q -batch -x "$dir/cmds" "$exe" 2>&1; rm -rf "$dir"; exit; fi
timeout 60 gdb -q -batch -x "$dir/cmds" "$exe" 2>&1 \
  | grep -E '^(\$[0-9]|type = )' | sed -E 's/0x[0-9a-f]+/ADDR/g'
rm -rf "$dir"
