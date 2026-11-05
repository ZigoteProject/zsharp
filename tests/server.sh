#!/usr/bin/env bash
# The build server: zs build asks it when it runs, and starts one when none does. A build it
# answers is the binary an in-process build makes, its errors and exit code come back, and
# zs server stop ends it.
set -u
cd "$(dirname "$0")/.."
t=$(mktemp -d); trap 'bin/zs server stop >/dev/null 2>&1; rm -rf "$t"' EXIT
export XDG_CACHE_HOME=$t/cache
unset ZS_NO_SERVER
# binaries compared have one name, each in a directory of its own: macOS's ad-hoc signature holds
# the binary's name
mkdir -p "$t/a" "$t/b" "$t/c"
bin/zs build tests/spans.zs -o "$t/a/exe" # none yet: built here, and one started
for i in $(seq 100); do ls "$t"/cache/zs/servers/*.sock >/dev/null 2>&1 && break; sleep 0.1; done
# whoever reaches the socket runs zs commands as this user: its directory is private, whatever the
# umask it was made under (stat -c is GNU's, stat -f BSD's, macOS's)
servers=$t/cache/zs/servers
echo "its directory: $(stat -c %a "$servers" 2>/dev/null || stat -f %OLp "$servers")"
bin/zs build tests/spans.zs -o "$t/b/exe" --time 2>"$t/time"
grep -q "^total (build server)" "$t/time" && echo "the server built it"
ZS_NO_SERVER=1 XDG_CACHE_HOME=$t/ref bin/zs build tests/spans.zs -o "$t/c/exe"
cmp -s "$t/a/exe" "$t/b/exe" && cmp -s "$t/b/exe" "$t/c/exe" && echo "the same binary as built in-process"
bin/zs build tests/err_yield.zs -o "$t/q" 2>"$t/err"
echo "an error: exit $?, $(head -1 "$t/err")"
bin/zs server stop
sleep 0.5
echo "stopped: $(ls "$servers" 2>/dev/null | wc -l | tr -d ' ') sockets left" # (tr: BSD's wc, macOS's, pads its count)
