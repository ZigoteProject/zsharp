#!/usr/bin/env bash
# Phase 6's exit test: the echo server (examples/echo) holding 10,000 connections for an hour,
# its memory sampled each minute, then stopped by a "quit" connection. The client sends a line
# on every connection each second and checks that the same bytes come back.
# Usage, in ./dev: bench/echo/soak.sh [seconds] [connections] [port]
set -eu
cd "$(dirname "$0")/../.."
seconds=${1:-3600}; n=${2:-10000}; port=${3:-9910}
dir=$(mktemp -d)
bin/zs build examples/echo/server.zs -o "$dir/server" --release
bin/zs build examples/echo/client.zs -o "$dir/client" --release
"$dir/server" "$port" > "$dir/server.log" 2>&1 & srv=$!
sleep 1
"$dir/client" "$port" "$n" "$seconds" 1000 quit > "$dir/client.log" 2>&1 & cli=$!
start=$(date +%s)
echo "minute  server RSS (KB)"
while kill -0 $cli 2>/dev/null; do
  echo "$(( ($(date +%s) - start) / 60 ))  $(awk '/VmRSS/ { print $2 }' /proc/$srv/status 2>/dev/null || echo gone)"
  for _ in $(seq 60); do kill -0 $cli 2>/dev/null && sleep 1; done
done
wait $cli && echo "client: $(cat "$dir/client.log")" || echo "client failed: $(cat "$dir/client.log")"
# the client's quit stops the server: give it a minute, then stop it
for _ in $(seq 60); do kill -0 $srv 2>/dev/null && sleep 1; done
kill -0 $srv 2>/dev/null && { kill $srv; echo "server didn't stop: killed"; }
wait $srv && echo "server: $(tail -1 "$dir/server.log")" || echo "server failed: $(cat "$dir/server.log")"
rm -rf "$dir"
