#!/usr/bin/env bash
# zs fmt writes a file whole or not at all: the new text goes to a file beside it, with the file's
# permissions, which then takes its place. A run stopped part-way through its write (here by the
# limit on a file's size, as a full disk stops one) leaves the file as it was, not cut short.
set -u
cd "$(dirname "$0")/../.."
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# spaced as nothing is, so every line changes: 400 lines, 4 KB formatted
for i in $(seq 400); do echo "let  v$i=$i"; done > "$t/a.zs"
cp "$t/a.zs" "$t/b.zs"
cp "$t/a.zs" "$t/as-written.zs"
chmod 640 "$t/a.zs"
bin/zs fmt "$t/a.zs"; echo "exit $?"
head -2 "$t/a.zs"
ls -l "$t/a.zs" | cut -c1-10
echo "$(ls "$t" | grep -c zsfmt) files left beside it"
# 2 KB at most: the write stops half-way, zs killed by SIGXFSZ (no core file; the subshell waits
# for it, not exec'ing it, so the shell's word on the signal goes where its output goes)
zs=$PWD/bin/zs
(cd "$t" && ulimit -c 0 && ulimit -f 2 && "$zs" fmt b.zs; true) >/dev/null 2>&1
cmp -s "$t/b.zs" "$t/as-written.zs" && echo "stopped: the file as it was" || echo "stopped: the file is $(wc -c < "$t/b.zs") bytes"
