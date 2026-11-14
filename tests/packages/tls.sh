#!/usr/bin/env bash
# packages/tls (proposal 0032), used as a path dependency by tests/packages/tls: the vendored
# Mbed TLS is the release c/VERSION names, and the program's output (a client and a server over
# loopback, with a certificate made as it starts) with nothing leaked. Built in a copy, so
# nothing is written into the checkout.
set -u
zs="$(pwd)/bin/zs"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
sums() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
echo "== the vendored source"
(cd packages/tls/c && sums -c SHA256SUMS | grep -v ': OK$'; echo "$(grep -c . SHA256SUMS) files checked")
[ "$(cd packages/tls/c && find mbedtls -type f | wc -l | tr -d ' ')" = "$(grep -c . packages/tls/c/SHA256SUMS)" ] || echo "a file in c/mbedtls that SHA256SUMS doesn't list"
mkdir -p "$t/packages" "$t/tests/packages"
cp -r packages/tls "$t/packages/" && cp -r tests/packages/tls "$t/tests/packages/"
cd "$t/tests/packages/tls" && rm -rf .zs-cache build
echo "== the program"
ZS_LEAKCHECK=1 timeout 600 "$zs" run --strict; echo "exit $?"
echo "== Mbed TLS's pointers, outside the package"
timeout 120 "$zs" check src/Handles.zs 2>&1 | grep -o "error: the fields of .*"
