#!/usr/bin/env bash
# The build server: zs build asks it when it runs, and starts one when none does. A build it
# answers is the binary an in-process build makes, its errors and exit code come back, and
# zs server stop ends it.
set -u
cd "$(dirname "$0")/.."
t=$(mktemp -d); trap 'bin/zs server stop >/dev/null 2>&1; rm -rf "$t"' EXIT
export XDG_CACHE_HOME=$t/cache
unset ZS_NO_SERVER
bin/zs build tests/spans.zs -o "$t/a" # none yet: built here, and one started
for i in $(seq 100); do ls "$t"/cache/zs/servers/*.sock >/dev/null 2>&1 && break; sleep 0.1; done
bin/zs build tests/spans.zs -o "$t/b" --time 2>"$t/time"
grep -q "^total (build server)" "$t/time" && echo "the server built it"
ZS_NO_SERVER=1 XDG_CACHE_HOME=$t/ref bin/zs build tests/spans.zs -o "$t/c"
cmp -s "$t/a" "$t/b" && cmp -s "$t/b" "$t/c" && echo "the same binary as built in-process"
bin/zs build tests/err_yield.zs -o "$t/q" 2>"$t/err"
echo "an error: exit $?, $(head -1 "$t/err")"
bin/zs server stop
sleep 0.5
echo "stopped: $(ls "$t"/cache/zs/servers/ 2>/dev/null | wc -l) sockets left"
