#!/usr/bin/env bash
# Symbolic links, pipes and devices in packages (POSIX's), against a local repository: zs.lock
# hashes a link as a link, never what it points at; zs vendor copies one only when it leads inside
# its package; a pipe in a vendored package, and a dependency's main that's a device, are errors,
# not reads that never end.
set -u
zs="$(pwd)/bin/zs"; t=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$t"' EXIT  # resolved, as the compiler names it (macOS: /var is /private/var)
l() { git -C "$t/linked" -c user.name=zs -c user.email=zs@example.invalid "$@" >/dev/null 2>&1; }
# the library, with a link out of it (to a file of this machine) and one inside it
mkdir -p "$t/linked" && cp -r tests/project/text/. "$t/linked/"
echo 'a secret' > "$t/secret"
ln -s "$t/secret" "$t/linked/NOTES"
ln -s src/Text.zs "$t/linked/Alias.zs"
l init -b main && l add -A && l commit -m v1 && l tag v1
mkdir -p "$t/app/src" && cd "$t/app"
printf '[package]\nname = "app"\n\n[dependencies]\nlinked = { git = "file://%s/linked", rev = "v1" }\n' "$t" > zs.toml
printf 'let main () =\n  println $"words {Linked.wordCount "a b c d"}"\n  0\n' > src/main.zs
"$zs" run 2>/dev/null
echo "== the file a link points at changes"
echo 'another secret' > "$t/secret"
if out=$("$zs" fetch 2>&1); then echo "fetched: the lock's hash is the link's, not the file's"; else echo "$out" | sed "s|$t|…|g"; fi
echo "== zs vendor and a link out of the package"
"$zs" vendor 2>&1 | sed "s|$t|…|g"
ls vendor 2>/dev/null | wc -l | tr -d ' ' | sed 's/^/packages vendored: /' # (tr: BSD's wc, macOS's, pads its count)
echo "== zs vendor and a link inside it"
l rm NOTES && l commit -m v2 && l tag v2
printf '[package]\nname = "app"\n\n[dependencies]\nlinked = { git = "file://%s/linked", rev = "v2" }\n' "$t" > zs.toml
"$zs" vendor 2>/dev/null
[ -L vendor/linked/Alias.zs ] && echo "vendor/linked/Alias.zs is a link to $(readlink vendor/linked/Alias.zs)"
rm -rf .zs-cache/deps
"$zs" run --offline 2>&1
echo "== a pipe in a vendored package"
mkfifo vendor/linked/pipe
timeout 120 "$zs" run --offline 2>&1 | head -1
rm -f vendor/linked/pipe
echo "== a dependency's main that's a device"
mkdir -p "$t/dev/src" "$t/devuser/src"
printf '[package]\nname = "dev"\nmain = "src/Dev.zs"\n' > "$t/dev/zs.toml"
ln -s /dev/null "$t/dev/src/Dev.zs"
printf '[package]\nname = "devuser"\n\n[dependencies]\ndev = { path = "../dev" }\n' > "$t/devuser/zs.toml"
printf 'let main () =\n  println Dev.tag\n  0\n' > "$t/devuser/src/main.zs"
(cd "$t/devuser" && timeout 120 "$zs" build 2>&1 | grep -o "[^ ]*Dev.zs isn't a regular file but a pipe or a device")
