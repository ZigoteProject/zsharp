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

# a dependency's name is its directory under .zs-cache/deps: one leading out of it is refused and
# fetch deletes nothing; a rev git would take as an option is refused too
mkdir -p "$t/keep"
printf '[package]\nname = "app"\n\n[dependencies]\n../../../keep = { git = "file:///nonexistent/x" }\n' > zs.toml
"$zs" fetch 2>&1 | grep -o "dependency '../../../keep': a name is letters, digits, - and _"
[ -d "$t/keep" ] && echo "../../../keep is still there"
printf '[package]\nname = "app"\n\n[dependencies]\ntext = { git = "file:///nonexistent/x", rev = "--orphan=x" }\n' > zs.toml
"$zs" fetch 2>&1 | grep -o "rev '--orphan=x' starts with -"

# versions (0018 item 2): minimal version selection over tags, as Go's. c has releases 1.1, 1.3,
# 1.4 and 2.0; a 1.0 asks for c 1.1 and b 1.0 for c 1.3, so a program asking for c 1.0, a and b
# gets c 1.3, not the newest; c's major 2 is another package, c2, in the same program
repo() { mkdir -p "$t/$1/src" && git -C "$t/$1" init -q -b main; }
release() { git -C "$t/$1" -c user.name=zs -c user.email=zs@example.invalid add -A >/dev/null && git -C "$t/$1" -c user.name=zs -c user.email=zs@example.invalid commit -qm "$2" && git -C "$t/$1" tag "v$2"; }
repo c
for v in 1.1.0 1.3.0 1.4.0 2.0.0; do
  printf '[package]\nname = "c"\nmain = "src/C.zs"\n' > "$t/c/zs.toml"
  printf '/// The release.\nlet release () = "%s"\n' "$v" > "$t/c/src/C.zs"
  release c "$v"
done
for p in a:1.1 b:1.3; do
  n=${p%%:*}; need=${p##*:}; repo "$n"
  printf '[package]\nname = "%s"\nmain = "src/%s.zs"\n\n[dependencies]\nc = { git = "file://%s/c", version = "%s" }\n' "$n" "$(echo $n | tr a-z A-Z)" "$t" "$need" > "$t/$n/zs.toml"
  printf '/// The release of c this one sees.\nlet sees () = C.release ()\n' > "$t/$n/src/$(echo $n | tr a-z A-Z).zs"
  release "$n" 1.0.0
done
mkdir -p "$t/diamond/src" && cd "$t/diamond"
printf '[package]\nname = "diamond"\n\n[dependencies]\na = { git = "file://%s/a", version = "1.0" }\nb = { git = "file://%s/b", version = "1.0" }\nc = { git = "file://%s/c", version = "1.0" }\nc2 = { git = "file://%s/c", version = "2.0" }\n' "$t" "$t" "$t" "$t" > zs.toml
echo 'let main () =
  println $"c {C.release ()}, a sees {A.sees ()}, b sees {B.sees ()}, c2 {C2.release ()}"
  0' > src/main.zs
"$zs" run 2>/dev/null
grep -o 'c = { git = "[^"]*", version = "[^"]*"' zs.lock | sed 's/git = "[^"]*", //'
rm -rf .zs-cache && "$zs" run 2>/dev/null | sed 's/^/(from zs.lock) /'
# zs update raises the program's own minimums in zs.toml to the newest releases
"$zs" update 2>/dev/null && grep -o '^c = { git = "[^"]*", version = "[^"]*"' zs.toml | sed 's/git = "[^"]*", //'
"$zs" run 2>/dev/null | sed 's/^/(updated) /'
sed -i 's/c = { git = "\([^"]*\)", version = "1.4.0" }/c = { git = "\1", version = "1.5" }/' zs.toml
"$zs" build 2>&1 | grep -o "c: no tag v1.5.0 or later below v2.0.0 (the newest is v1.4.0)"
printf '[package]\nname = "both"\n\n[dependencies]\nc = { git = "file:///x", rev = "main", version = "1.0" }\n' > zs.toml
"$zs" fetch 2>&1 | grep -o "dependency 'c' has both rev and version; keep one"
