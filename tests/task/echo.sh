#!/usr/bin/env bash
# The echo server (examples/echo) with 1,000 connections for 2 seconds, each sending a line a
# tenth of a second and checking the echo; then the client's "quit" stops the server. With
# --valgrind, the server runs under valgrind. Prints the client's summary without its count of
# round trips (which depends on the machine), and how the server ended.
set -u
cd "$(dirname "$0")/../.."
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
port=$((20000 + RANDOM % 20000))
timeout 60 bin/zs build examples/echo/server.zs -o "$dir/server" && timeout 60 bin/zs build examples/echo/client.zs -o "$dir/client" || exit 1
run=(); [ "${1:-}" = --valgrind ] && run=(valgrind -q --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=99)
timeout 120 "${run[@]}" "$dir/server" $port > "$dir/server.log" 2>&1 & srv=$!
sleep $([ ${#run[@]} -gt 0 ] && echo 3 || echo 0.3)
timeout 60 "$dir/client" $port 1000 2 100 quit | sed -E 's/, [0-9]+ round trips//'
wait $srv; echo "server exit $?"
sed -E "s/port [0-9]+/port PORT/" "$dir/server.log"
