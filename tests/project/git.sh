#!/usr/bin/env bash
# Git dependencies, against a local repository (no network): fetching a tag, zs.lock pinning
# the commit, a branch rev, zs update, and re-fetching from the lock.
set -u
zs="$(pwd)/bin/zs"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
g() { git -C "$t/text" -c user.name=zs -c user.email=zs@example.invalid "$@" >/dev/null 2>&1; }
lockCommit() { grep -o 'commit = "[0-9a-f]*"' "$t/app/zs.lock" | grep -o '[0-9a-f]\{40\}'; }
head() { git -C "$t/text" rev-parse "$1"; }

# the library: v1 (a tag), then main moves on with a new function
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
[ "$(lockCommit)" = "$(head v1)" ] && echo "zs.lock pins v1"

echo '
/// Upper-cases the text.
let shout (s: string) = String.toUpper s' >> "$t/text/src/Text.zs" && g commit -am "add shout"
"$zs" run 2>&1 | sed 's/^/(v1 still) /'
[ "$(lockCommit)" = "$(head v1)" ] && echo "zs.lock still pins v1"

# a branch rev: resolved again (the rev changed), then pinned
sed -i 's/rev = "v1"/rev = "main"/' zs.toml
sed -i 's/println \$"words {Text.wordCount "a b c"}"/println $"words {Text.wordCount "a b c"} {Text.shout "hi"}"/' src/main.zs
"$zs" run 2>/dev/null
[ "$(lockCommit)" = "$(head main)" ] && echo "zs.lock pins main"

echo '
/// Twice the text.
let twice (s: string) = s + s' >> "$t/text/src/Text.zs" && g commit -am "add twice"
"$zs" build >/dev/null 2>&1 && [ "$(lockCommit)" != "$(head main)" ] && echo "a build keeps the locked commit"
"$zs" update 2>/dev/null && [ "$(lockCommit)" = "$(head main)" ] && echo "zs update moves to the newest main"

# a fresh checkout (no .zs-cache) fetches the locked commit again
rm -rf .zs-cache && "$zs" check src/main.zs 2>/dev/null && echo "re-fetched from zs.lock"
sed -i 's|file://[^"]*|file:///nonexistent/text|' zs.toml && rm -rf .zs-cache
"$zs" build 2>&1 | grep -o "zs: git dependency 'text' (file:///nonexistent/text main):" 
