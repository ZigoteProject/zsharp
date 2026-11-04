#!/usr/bin/env bash
# a panic's backtrace (ZS_BACKTRACE unset or 1) names the Z# functions on the way, from the
# program's own symbol table, the runtime's frames left out and the program's main last; with
# ZS_BACKTRACE=0 there is none. Linux (the ELF reader; elsewhere the C library's symbolizer).
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
"$zs" build tests/backtrace/prog.zs -o "$t/prog" || exit 1
echo "with a backtrace:"
ZS_BACKTRACE=1 "$t/prog" 2>&1; echo "exit $?"
echo "without:"
ZS_BACKTRACE=0 "$t/prog" 2>&1; echo "exit $?"
echo "a release build, the same names:"
"$zs" build tests/backtrace/prog.zs --release -o "$t/rel" || exit 1
ZS_BACKTRACE=1 "$t/rel" 2>&1 | head -2; echo "exit ${PIPESTATUS[0]}"
echo "panics on four threads at once, ten runs: one report each, nothing corrupted"
"$zs" build tests/backtrace/threads.zs -o "$t/threads" || exit 1
for i in 1 2 3 4 5 6 7 8 9 10; do
  out=$(ZS_WORKERS=4 ZS_BACKTRACE=1 "$t/threads" 2>&1)
  echo "$(echo "$out" | grep -c '^panic: boom') $(echo "$out" | grep -c 'corrupt\|malloc\|Segmentation\|free()')"
done | sort | uniq -c | sed 's/^ *//'

