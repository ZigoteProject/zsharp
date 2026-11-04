#!/usr/bin/env bash
# Workspaces (0018 item 8): [workspace] members in a root zs.toml; zs build, zs test, zs fetch and
# zs tree at the root run over every member; one zs.lock and one .zs-cache at the root; a lock
# inside a member is an error naming the root.
set -u
zs="$(pwd)/bin/zs"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
g() { git -C "$t/words" -c user.name=zs -c user.email=zs@example.invalid "$@" >/dev/null 2>&1; }
mkdir -p "$t/words" && cp -r tests/project/text/. "$t/words/" && g init -b main && g add -A && g commit -m v1 && g tag v1
mkdir -p "$t/ws/libs/text" "$t/ws/app/src" "$t/ws/tool/src"
cp -r tests/project/text/. "$t/ws/libs/text/"
printf '[workspace]\nmembers = ["app", "tool", "libs/*"]\n' > "$t/ws/zs.toml"
cat > "$t/ws/app/zs.toml" <<TOML
[package]
name = "app"

[dependencies]
text = { path = "../libs/text" }
words = { git = "file://$t/words", rev = "v1" }
TOML
cat > "$t/ws/app/src/main.zs" <<'ZS'
open Testing

let main () =
  println $"{Text.wordCount "a b c"} {Words.wordCount "d e"}"
  0

[<Tests>]
let tests = testList "app" [ test "counts" (fun () -> assert (Text.wordCount "a b" = 2)) ]
ZS
printf '[package]\nname = "tool"\n' > "$t/ws/tool/zs.toml"
printf 'let main () =\n  println "tool"\n  0\n' > "$t/ws/tool/src/main.zs"
cd "$t/ws"
echo "== zs build at the root"
"$zs" build 2>&1 | grep -v '^fetching\|^resolving'
(cd app && ./build/app) && (cd tool && ./build/tool)
echo "== one lock and one cache, at the root"
ls zs.lock .zs-cache/deps; ls app/zs.lock app/.zs-cache 2>&1 | sed 's/:.*/: none/'
echo "== zs test at the root"
"$zs" test 2>&1 | sed "s|$t/||"
echo "== zs tree at the root"
"$zs" tree | sed "s|$t|…|g; s|commit [0-9a-f]*|commit …|"
echo "== a lock inside a member"
touch app/zs.lock
(cd app && "$zs" build 2>&1 | head -1)
rm app/zs.lock
echo "== zs run and zs add at the root"
"$zs" run 2>&1 | head -1
"$zs" add ../words 2>&1 | head -1
