#!/usr/bin/env bash
# The guide's accept loop (tests/task/emfile.zs) with 64 descriptors: 100 clients connect, so its
# accepts fail for want of descriptors, then leave. It sees them leave while it keeps failing to
# accept (the loop looks at its descriptors however busy its tasks keep it), closes what it held,
# takes the connections still queued and then a "quit", and it pauses after each failed accept
# rather than spin. bash's /dev/tcp makes the clients.
set -u
cd "$(dirname "$0")/../.."
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
# below every system's ephemeral ports (Linux's from 32768, macOS's and Windows's from 49152), so
# no client socket of an earlier run, still closing, holds the port the server listens on
port=$((10000 + RANDOM % 20000))
timeout 60 bin/zs build tests/task/emfile.zs -o "$dir/server" || exit 1
(ulimit -n 64 && exec timeout 30 "$dir/server" $port) > "$dir/server.log" 2>&1 & srv=$!
sleep 0.5
fds=()
for i in $(seq 100); do exec {fd}<>"/dev/tcp/127.0.0.1/$port" && fds+=($fd); done
sleep 1
for fd in "${fds[@]}"; do exec {fd}>&-; done
sleep 1
exec {q}<>"/dev/tcp/127.0.0.1/$port" && printf quit >&$q
wait $srv; echo "server exit $?"
exec {q}>&-
cat "$dir/server.log"
