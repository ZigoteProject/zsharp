#!/usr/bin/env bash
# zs build -g: gdb shows heap values through their objects: a list's cell (count, head, tail) and
# the next, an array's count, length and elements, a tree's node with its fields, a tagged
# union's cell's case and that case's fields (the other cases' lie over the same bytes), an
# option over a string as the string, a ref's value. Addresses are left out of the output.
zs=${1:-bin/zs}; exe=$(mktemp)
timeout 30 "$zs" build tests/debug/heap.zs -g -o "$exe" || exit 1
timeout 30 gdb -q -batch -ex "break heap.zs:18" -ex run -ex "print *xs" -ex "print *xs->tail" -ex "print xs->tail->tail->tail" \
  -ex "print *names" -ex "print *names->elements[1]" -ex "print *tree" -ex "print token->case" -ex "print token->Word" \
  -ex "print *some" -ex "print *cell" -ex "whatis xs" -ex "whatis tree" -ex kill "$exe" 2>&1 \
  | grep -E '^(\$[0-9]|type = )' | sed -E 's/0x[0-9a-f]+/ADDR/g'
rm -f "$exe"
