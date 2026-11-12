#!/usr/bin/env bash
# packages/http (proposal 0032), used as a path dependency by tests/packages/http: the vendored
# llhttp is the release c/VERSION names, the program's output (a server and a client over
# loopback, plain and under TLS) with nothing leaked, and examples/service (HTTP over SQLite)
# and examples/echo/http answering requests. Built in a copy, so nothing is written into the checkout.
set -u
zs="$(pwd)/bin/zs"; t=$(mktemp -d); trap 'kill $server 2>/dev/null; rm -rf "$t"' EXIT; server=
sums() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
echo "== the vendored source"
(cd packages/http/c && sums -c SHA256SUMS)
mkdir -p "$t/packages" "$t/tests/packages" "$t/examples"
cp -r packages/http packages/tls packages/sqlite "$t/packages/" && cp -r tests/packages/http "$t/tests/packages/" && cp -r examples/service "$t/examples/" && mkdir -p "$t/examples/echo" && cp -r examples/echo/http "$t/examples/echo/"
cd "$t/tests/packages/http" && rm -rf .zs-cache build
echo "== the program"
ZS_LEAKCHECK=1 timeout 600 "$zs" run --strict; echo "exit $?"
echo "== Http.parseRequest, and a property over any bytes (zs fuzz runs the same one)"
timeout 600 "$zs" test src/Wire.zs 2>&1 | tail -1
echo "== examples/service"
cd "$t/examples/service" && rm -rf .zs-cache build && timeout 600 "$zs" build --strict >/dev/null || echo "the build failed"
./build/service 0 "$t/notes.db" 2> "$t/service.log" & server=$!
for _ in $(seq 100); do grep -q listening "$t/service.log" && break; sleep 0.1; done
port=$(sed -n 's|.*127.0.0.1:||p' "$t/service.log")
# one request on a connection of bash's own: the status and the body
ask() { exec 3<>"/dev/tcp/127.0.0.1/$port" && printf '%s %s HTTP/1.1\r\nHost: x\r\nConnection: close\r\nContent-Length: %s\r\n\r\n%s' "$1" "$2" "${#3}" "$3" >&3 && tr -d '\r' <&3 | sed -n '1p;$p' | paste -sd' ' -; exec 3<&-; }
ask POST /notes 'buy milk'
ask POST /notes "it's \"quoted\"; drop table notes"
ask POST /notes ''
ask GET /notes ''
ask DELETE /notes/1 ''
ask DELETE /notes/1 ''
ask GET /notes ''
ask GET /elsewhere ''
kill $server 2>/dev/null; wait $server 2>/dev/null
echo "== examples/echo/http"
cd "$t/examples/echo/http" && timeout 600 "$zs" build --strict >/dev/null || echo "the build failed"
./build/echo-http 0 2> "$t/echo.log" & server=$!
for _ in $(seq 100); do grep -q echoing "$t/echo.log" && break; sleep 0.1; done
port=$(sed -n 's|.*127.0.0.1:||p' "$t/echo.log")
ask POST / 'hello, echo'
ask GET /some/path ''
