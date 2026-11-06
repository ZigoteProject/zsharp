#!/usr/bin/env bash
# What zs writes for a dependency stays out of the dependency's directory: a git dependency's and
# a vendored one's import c is saved in the project's .zs-cache (its file checked as a program
# too), so the lock's hash still holds at the next build; a .zs-cache/cimport a dependency holds
# as a symbolic link leads nothing out, nor does a [package] name that is a path; a package's
# provider is built with the project's checkouts (its git dependency not fetched again, into it),
# and built again when a file it's built from changes, the library's too; the project's own
# .zs-cache as a symbolic link is an error, not a write through it. A git dependency's own file,
# with a git dependency of its own, checked (zs check) or opened in the language server, fetches
# nothing into its checkout, and a name its provided module defines is refused a rename as
# provided.
set -u
zs="$(pwd)/bin/zs"; t=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$t"' EXIT  # resolved, as the compiler names it (macOS: /var is /private/var)
g() { git -C "$1" -c user.name=zs -c user.email=zs@example.invalid "${@:2}" >/dev/null 2>&1; }
# an edit in place, as GNU's sed and BSD's (macOS's) both take it
edit() { sed "$1" "$2" > "$2.new" && mv "$2.new" "$2"; }
mkdir -p "$t/victim"
victims() { ls -A "$t/victim" | wc -l | tr -d ' ' | sed 's/^/  files where the link leads: /'; } # (tr: BSD's wc, macOS's, pads its count)

echo "== a git dependency's import c"
mkdir -p "$t/cdep/src" "$t/app/src"
printf '[package]\nname = "cdep"\nmain = "src/Cdep.zs"\n' > "$t/cdep/zs.toml"
printf '#define CDEP_SIZE 3\n' > "$t/cdep/src/cdep.h"
printf 'import c "cdep.h"\n\nlet size () = CDEP_SIZE\n' > "$t/cdep/src/Cdep.zs"
g "$t/cdep" init -b main && g "$t/cdep" add -A && g "$t/cdep" commit -m v1 && g "$t/cdep" tag v1
cat > "$t/app/zs.toml" <<TOML
[package]
name = "app"

[dependencies]
cdep = { git = "file://$t/cdep", rev = "v1" }
TOML
printf 'let main () =\n  println $"size {Cdep.size ()}"\n  0\n' > "$t/app/src/main.zs"
cd "$t/app"
"$zs" run 2>&1 | grep -v -e '^fetching ' -e '^resolving '
"$zs" run 2>&1
echo "the checkout: $(ls -A .zs-cache/deps/cdep | tr '\n' ' ')"
echo "its cache: $(cd .zs-cache && ls -d pkgs/*/cimport/* | sed 's|/cdep-[0-9a-f]*/|/cdep-<hash>/|' | tr '\n' ' ')"
# the dependency's own file checked as a program, as an editor opening it does: its cache too
"$zs" doc .zs-cache/deps/cdep/src/Cdep.zs >/dev/null 2>&1
echo "the checkout, its file checked: $(ls -A .zs-cache/deps/cdep | tr '\n' ' ')"
echo "== vendored"
"$zs" vendor
rm -rf .zs-cache
"$zs" run 2>&1
"$zs" run 2>&1
find vendor -type f | wc -l | tr -d ' ' | sed 's/^/files in vendor: /'

echo "== a dependency whose .zs-cache/cimport is a symbolic link"
mkdir -p "$t/evil/src" "$t/evil/.zs-cache" "$t/use/src"
printf '[package]\nname = "evil"\nmain = "src/Evil.zs"\n' > "$t/evil/zs.toml"
printf '#define EVIL_SIZE 5\n' > "$t/evil/src/evil.h"
printf 'import c "evil.h"\n\nlet size () = EVIL_SIZE\n' > "$t/evil/src/Evil.zs"
ln -s "$t/victim" "$t/evil/.zs-cache/cimport"
printf '[package]\nname = "use"\n\n[dependencies]\nevil = { path = "../evil" }\n' > "$t/use/zs.toml"
printf 'let main () =\n  println $"size {Evil.size ()}"\n  0\n' > "$t/use/src/main.zs"
(cd "$t/use" && "$zs" run 2>&1)
victims

echo "== a dependency whose name is a path"
mkdir -p "$t/esc/src" "$t/escapp/src"
printf '[package]\nname = "../../../escaped"\nmain = "src/Esc.zs"\n' > "$t/esc/zs.toml"
printf '#define ESC_SIZE 6\n' > "$t/esc/src/esc.h"
printf 'import c "esc.h"\n\nlet size () = ESC_SIZE\n' > "$t/esc/src/Esc.zs"
printf '[package]\nname = "escapp"\n\n[dependencies]\nesc = { path = "../esc" }\n' > "$t/escapp/zs.toml"
printf 'let main () =\n  println $"size {Esc.size ()}"\n  0\n' > "$t/escapp/src/main.zs"
(cd "$t/escapp" && "$zs" run 2>&1)
echo "its cache: $(cd "$t/escapp/.zs-cache" && ls -d pkgs/*/cimport/* | sed 's|/package-[0-9a-f]*/|/package-<hash>/|' | tr '\n' ' ')"
echo "  files where the name leads: $(ls "$t" | grep -c '^escaped')"

echo "== the project's own .zs-cache, a symbolic link"
mkdir -p "$t/own/src"
printf '[package]\nname = "own"\n' > "$t/own/zs.toml"
printf '#define OWN_SIZE 4\n' > "$t/own/src/own.h"
printf 'import c "own.h"\n\nlet main () =\n  println $"size {OWN_SIZE}"\n  0\n' > "$t/own/src/main.zs"
ln -s "$t/victim" "$t/own/.zs-cache"
(cd "$t/own" && "$zs" run 2>&1 | grep -v '^ [ 0-9]* | ' | sed "s|$t|…|g")
victims

echo "== a package's provider, with a path and a git dependency of its own"
mkdir -p "$t/words/src" "$t/helper/src" "$t/gen" "$t/prov/src"
printf '[package]\nname = "words"\nmain = "src/Words.zs"\n' > "$t/words/zs.toml"
printf 'let word = "world"\n' > "$t/words/src/Words.zs"
g "$t/words" init -b main && g "$t/words" add -A && g "$t/words" commit -m v1 && g "$t/words" tag v1
printf '[package]\nname = "helper"\nmain = "src/Helper.zs"\n' > "$t/helper/zs.toml"
printf 'let word = "hello"\n' > "$t/helper/src/Helper.zs"
cat > "$t/gen/zs.toml" <<TOML
[package]
name = "gen"

[dependencies]
helper = { path = "../helper" }
words = { git = "file://$t/words", rev = "v1" }

[provider]
main = "Provider.zs"
TOML
cat > "$t/gen/Provider.zs" <<'ZS'
// the gen provider: a greeting from the packages it depends on
let main () =
  println "// provided by gen 0.1"
  println ""
  println $"let greeting = \"{Helper.word} {Words.word}\""
  0
ZS
printf '[package]\nname = "prov"\n\n[dependencies]\ngen = { path = "../gen" }\n' > "$t/prov/zs.toml"
printf 'import gen "x"\n\nlet main () =\n  println greeting\n  0\n' > "$t/prov/src/main.zs"
cd "$t/prov"
"$zs" run 2>&1 | grep -v -e '^fetching ' -e '^resolving '
echo "gen: $(ls -A "$t/gen" | tr '\n' ' ')"
echo "-- the provider's own file changed"
edit 's/{Helper.word} {Words.word}/{Helper.word}, {Words.word}/' "$t/gen/Provider.zs"
"$zs" run 2>&1
echo "-- a package it depends on changed"
edit 's/hello/hi/' "$t/helper/src/Helper.zs"
"$zs" run 2>&1
for d in gen helper; do echo "$d: $(ls -A "$t/$d" | tr '\n' ' ')"; done
echo "the checkout of words: $(ls -A .zs-cache/deps/words | tr '\n' ' ')"
echo "-- the library it's built with changed (ZS_LIB)"
cp -R "${zs%/bin/zs}/lib" "$t/lib"
key() { cat .zs-cache/providers/bin/zs-provider-gen.key; }
ZS_LIB=$t/lib "$zs" run >/dev/null 2>&1
before=$(key)
printf '\n// the library edited\n' >> "$t/lib/prelude.zs"
ZS_LIB=$t/lib "$zs" run 2>&1
if [ "$(key)" != "$before" ]; then echo "  the provider built again"; else echo "  the provider not built again"; fi

echo "== a git dependency's own file, with a git dependency of its own: checked, and opened in an editor"
mkdir -p "$t/wxd/src" "$t/wxapp/src"
cat > "$t/wxd/zs.toml" <<TOML
[package]
name = "wxd"
main = "src/Wxd.zs"

[dependencies]
words = { git = "file://$t/words", rev = "v1" }
TOML
printf '{ "city": "Oslo" }\n' > "$t/wxd/src/w.json"
printf 'module W = import json "w.json"\n\nlet cityOf (s: string) =\n  match W.parse s with\n  | Ok w -> w.city\n  | Error e -> e\n\nlet word () = Words.word\n' > "$t/wxd/src/Wxd.zs"
g "$t/wxd" init -b main && g "$t/wxd" add -A && g "$t/wxd" commit -m v1 && g "$t/wxd" tag v1
cat > "$t/wxapp/zs.toml" <<TOML
[package]
name = "wxapp"

[dependencies]
wxd = { git = "file://$t/wxd", rev = "v1" }
TOML
printf 'let main () =\n  println (Wxd.word ())\n  0\n' > "$t/wxapp/src/main.zs"
cd "$t/wxapp"
"$zs" run 2>&1 | grep -v -e '^fetching ' -e '^resolving '
# zs check on its file (an error: it has no main) fetches nothing into the checkout
"$zs" check .zs-cache/deps/wxd/src/Wxd.zs >/dev/null 2>&1
echo "the checkout, its file checked: $(ls -A .zs-cache/deps/wxd | tr '\n' ' ')"
# the language server on its file: a rename of the provided module's field w.city (line 4)
f="$t/wxapp/.zs-cache/deps/wxd/src/Wxd.zs"
src=$(sed 's/\\/\\\\/g; s/"/\\"/g' "$f" | awk '{printf "%s\\n", $0}')
frame() { printf 'Content-Length: %d\r\n\r\n%s' "$(printf '%s' "$1" | wc -c)" "$1"; }
{ frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}'
  frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file://'"$f"'","languageId":"zsharp","version":1,"text":"'"$src"'"}}}'
  frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/rename","params":{"textDocument":{"uri":"file://'"$f"'"},"position":{"line":4,"character":15},"newName":"town"}}'
  frame '{"jsonrpc":"2.0","id":3,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | "$zs" lsp | grep -o '"id":2,"error":{"code":-32602,"message":"[^"]*"' | sed 's/^.*"message":"\(.*\)"$/  \1/'
echo "the checkout, its file opened: $(ls -A .zs-cache/deps/wxd | tr '\n' ' ')"
