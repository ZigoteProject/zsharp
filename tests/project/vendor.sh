#!/usr/bin/env bash
# Integrity (0018 item 6), against a local repository: zs.lock hashes each git dependency's files;
# an edited checkout is restored from its commit at the next fetch; zs vendor copies the
# dependencies into vendor/, read from there with no network; a vendored copy that was edited is
# an error; --offline is an error instead of a fetch.
set -u
zs="$(pwd)/bin/zs"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
g() { git -C "$t/text" -c user.name=zs -c user.email=zs@example.invalid "$@" >/dev/null 2>&1; }
mkdir -p "$t/text" && cp -r tests/project/text/. "$t/text/" && g init -b main && g add -A && g commit -m v1 && g tag v1
mkdir -p "$t/app/src"
cat > "$t/app/zs.toml" <<TOML
[package]
name = "app"

[dependencies]
text = { git = "file://$t/text", rev = "v1" }
TOML
echo 'let main () =
  println $"words {Text.wordCount "a b c"}"
  0' > "$t/app/src/main.zs"
cd "$t/app"
"$zs" run 2>/dev/null
grep -c 'hash = "[0-9a-f]*"' zs.lock | sed 's/^/zs.lock entries with a hash: /'
echo "== an edited checkout, restored by the next fetch"
echo 'let extra = 1' >> .zs-cache/deps/text/src/Text.zs
"$zs" fetch && grep -c extra .zs-cache/deps/text/src/Text.zs
echo "== vendored"
"$zs" vendor | sed "s|$t|…|g"
ls vendor/text | tr '\n' ' '; echo
rm -rf .zs-cache/deps
"$zs" run --offline 2>&1 | sed "s|$t|…|g"
ls .zs-cache/deps 2>/dev/null | wc -l | sed 's/^/checkouts made: /'
echo "== a vendored copy that was edited"
echo 'let extra = 1' >> vendor/text/src/Text.zs
"$zs" run 2>&1 | sed "s|$t|…|g" | head -1
echo "== --offline with nothing fetched"
rm -rf vendor .zs-cache
"$zs" run --offline 2>&1 | sed "s|$t|…|g" | head -1
ZS_OFFLINE=1 "$zs" run 2>&1 | sed "s|$t|…|g" | head -1
