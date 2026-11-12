#!/usr/bin/env bash
# packages/sqlite (proposal 0032), used as a path dependency by tests/packages/sqlite: the
# vendored amalgamation is the release c/VERSION names, the program's output with nothing
# leaked, and a connection handed to another thread refused when compiling. Built in a copy,
# so nothing is written into the checkout.
set -u
zs="$(pwd)/bin/zs"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
echo "== the vendored source"
(cd packages/sqlite/c && if command -v sha256sum >/dev/null; then sha256sum -c SHA256SUMS; else shasum -a 256 -c SHA256SUMS; fi)
mkdir -p "$t/packages" "$t/tests/packages"
cp -r packages/sqlite "$t/packages/" && cp -r tests/packages/sqlite "$t/tests/packages/"
cd "$t/tests/packages/sqlite" && rm -rf .zs-cache build
echo "== the program"
ZS_LEAKCHECK=1 timeout 600 "$zs" run --strict; echo "exit $?"
echo "== across threads, and a borrowed column outside unsafe"
timeout 120 "$zs" check src/Shared.zs 2>&1 | grep -o "captures 'db' : Sqlite.Db, which holds [^,]*, which can't be shared between threads\|error: .*textSpan.*"
