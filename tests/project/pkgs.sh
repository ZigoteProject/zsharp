#!/usr/bin/env bash
# Packages (0018, items 3, 5 and 7): zs add writes a dependency into zs.toml and fetches it, zs
# remove takes one out, zs tree shows what was resolved; a module under an internal/ directory
# is the package's own; a microcontroller build names a dependency that uses Std; a
# dependency's manifest that names a main outside it, a size past an int or is too large is an
# error, not a read of another file, an overflow or a read of any size.
set -u
zs="$(pwd)/bin/zs"; t=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$t"' EXIT  # resolved, as the compiler names it (macOS: /var is /private/var)
cp -r tests/project/two tests/project/alpha tests/project/beta tests/project/cwords tests/project/text "$t/"
cd "$t/two"
echo "== zs tree"
"$zs" tree
echo "== zs add ../text, zs remove alpha"
"$zs" add ../text
"$zs" remove alpha
sed -n '/\[dependencies\]/,$p' zs.toml
"$zs" tree
echo "== what isn't there"
"$zs" remove yaml; echo "exit $?"
out=$("$zs" add ../nowhere 2>&1); code=$?; echo "$out" | sed "s|$t|…|"; echo "exit $code"
echo "== a git dependency, as written (not fetched here)"
mkdir -p "$t/g" && printf '[package]\nname = "g"\n' > "$t/g/zs.toml"
(cd "$t/g" && "$zs" add https://example.invalid/someone/json.git@1.2 2>/dev/null | head -1; "$zs" add git@github.com:someone/json@v1 2>/dev/null | head -1; "$zs" add https://example.invalid/t.git --rev main 2>/dev/null | head -1; sed -n '/\[dependencies\]/,$p' zs.toml)
echo "== an internal module (box/src/internal/Secret.zs)"
mkdir -p "$t/box/src/internal" "$t/app/src"
printf '[package]\nname = "box"\nversion = "0.2.0"\nmain = "src/Box.zs"\n' > "$t/box/zs.toml"
printf 'let x = 41\n' > "$t/box/src/internal/Secret.zs"
printf 'let y = Internal.Secret.x + 1\n' > "$t/box/src/Pub.zs"
printf 'let value = Pub.y\n' > "$t/box/src/Box.zs"
printf '[package]\nname = "app"\nmain = "src/main.zs"\n\n[dependencies]\nbox = { path = "../box" }\n' > "$t/app/zs.toml"
printf 'let main () =\n  println $"{Box.value} {Box.Pub.y}"\n  0\n' > "$t/app/src/main.zs"
(cd "$t/app" && "$zs" run 2>&1)
printf 'let main () =\n  println $"{Box.Internal.Secret.x}"\n  0\n' > "$t/app/src/main.zs"
(cd "$t/app" && "$zs" run 2>&1 | grep -v '^ [ 0-9]* | ')
echo "== Std in a chip build's dependency"
mkdir -p "$t/logger/src" "$t/chip/src"
printf '[package]\nname = "logger"\nmain = "src/Logger.zs"\n' > "$t/logger/zs.toml"
printf 'let read (p: string) = File.readAllText p\nlet tag = "log"\n' > "$t/logger/src/Logger.zs"
printf '[package]\nname = "chip"\nmain = "src/main.zs"\ntarget = "cortex-m4"\n\n[dependencies]\nlogger = { path = "../logger" }\n' > "$t/chip/zs.toml"
printf 'let main () =\n  println Logger.tag\n  0\n' > "$t/chip/src/main.zs"
(cd "$t/chip" && "$zs" build 2>&1 | grep -v '^ [ 0-9]* | '; echo "exit ${PIPESTATUS[0]}")
echo "== a dependency's manifest: its main inside it, a size that fits, at most 1 MB"
mkdir -p "$t/evil" "$t/user/src"
printf '[package]\nname = "user"\n\n[dependencies]\nevil = { path = "../evil" }\n' > "$t/user/zs.toml"
printf 'let main () =\n  0\n' > "$t/user/src/main.zs"
printf '[package]\nname = "evil"\nmain = "/dev/stdin"\n' > "$t/evil/zs.toml"
(cd "$t/user" && "$zs" build 2>&1 | sed "s|$t|…|")
printf '[package]\nname = "evil"\n\n[target.cortex-m4]\nheap = "9000000000000000M"\n' > "$t/evil/zs.toml"
(cd "$t/user" && "$zs" build 2>&1 | sed "s|$t|…|")
head -c 1100000 /dev/zero | tr '\0' '#' > "$t/evil/zs.toml"
(cd "$t/user" && "$zs" build 2>&1 | sed "s|$t|…|")
