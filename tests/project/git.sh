#!/usr/bin/env bash
# Git dependencies, against a local repository (no network): fetching a tag, zs.lock pinning
# the commit, a branch rev, zs update, re-fetching from the lock, the default branch, what the
# lock keeps, and a packaged provider built against the lock's checkouts.
set -u
zs="$(pwd)/bin/zs"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# the repositories made here keep their files as written: git for Windows' core.autocrlf=true
# warns, on each add, that their LF will be CRLF
git() { command git -c core.autocrlf=false "$@"; }
g() { git -C "$t/text" -c user.name=zs -c user.email=zs@example.invalid "$@" >/dev/null 2>&1; }
lockCommit() { grep -o 'commit = "[0-9a-f]*"' "$t/app/zs.lock" | grep -o '[0-9a-f]\{40\}'; }
head() { git -C "$t/text" rev-parse "$1"; }
# an edit in place, as GNU's sed and BSD's (macOS's) both take it
edit() { sed "$1" "$2" > "$2.new" && mv "$2.new" "$2"; }

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
edit 's/rev = "v1"/rev = "main"/' zs.toml
edit 's/println \$"words {Text.wordCount "a b c"}"/println $"words {Text.wordCount "a b c"} {Text.shout "hi"}"/' src/main.zs
"$zs" run 2>/dev/null
[ "$(lockCommit)" = "$(head main)" ] && echo "zs.lock pins main"

echo '
/// Twice the text.
let twice (s: string) = s + s' >> "$t/text/src/Text.zs" && g commit -am "add twice"
"$zs" build >/dev/null 2>&1 && [ "$(lockCommit)" != "$(head main)" ] && echo "a build keeps the locked commit"
"$zs" update 2>/dev/null && [ "$(lockCommit)" = "$(head main)" ] && echo "zs update moves to the newest main"

# a fresh checkout (no .zs-cache) fetches the locked commit again
rm -rf .zs-cache && "$zs" check src/main.zs 2>/dev/null && echo "re-fetched from zs.lock"
edit 's|file://[^"]*|file:///nonexistent/text|' zs.toml && rm -rf .zs-cache
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
edit 's/c = { git = "\([^"]*\)", version = "1.4.0" }/c = { git = "\1", version = "1.5" }/' zs.toml
"$zs" build 2>&1 | grep -o "c: no tag v1.5.0 or later below v2.0.0 (the newest is v1.4.0)"
printf '[package]\nname = "both"\n\n[dependencies]\nc = { git = "file:///x", rev = "main", version = "1.0" }\n' > zs.toml
"$zs" fetch 2>&1 | grep -o "dependency 'c' has both rev and version; keep one"

# a dependency on the default branch (no rev): locked with rev = "", which every later fetch reads
mkdir -p "$t/branch/src" && cd "$t/branch"
printf '[package]\nname = "branch"\n\n[dependencies]\ntext = { git = "file://%s/text" }\n' "$t" > zs.toml
printf 'let main () =\n  println $"words {Text.wordCount "a b"}"\n  0\n' > src/main.zs
"$zs" run 2>/dev/null
"$zs" run 2>&1 | sed 's/^/(again) /'
grep -o 'rev = "[^"]*"' zs.lock

# zs.lock keeps what the manifests ask for: zs remove takes a release out of it, and a release
# made a rev builds the rev, not the release the lock had
mkdir -p "$t/prune/src" && cd "$t/prune"
printf '[package]\nname = "prune"\n\n[dependencies]\nc = { git = "file://%s/c", version = "1.1" }\n' "$t" > zs.toml
printf 'let main () =\n  println $"c {C.release ()}"\n  0\n' > src/main.zs
"$zs" run 2>/dev/null
"$zs" remove c 2>/dev/null
grep -c '^c = ' zs.lock | sed 's/^/zs.lock entries for c: /'
printf '[package]\nname = "prune"\n\n[dependencies]\nc = { git = "file://%s/c", version = "1.1" }\n' "$t" > zs.toml
"$zs" run 2>/dev/null
edit 's/version = "1.1"/rev = "v1.4.0"/' zs.toml
"$zs" run 2>/dev/null
grep -o '^c = { git = "[^"]*", [a-z]* = "[^"]*"' zs.lock | sed 's/git = "[^"]*", //'

# a lock entry's name is a directory under .zs-cache/deps, as a manifest's is: one leading out of
# it deletes nothing, and leaves the lock
mkdir -p "$t/lockname/src" "$t/lockname/.zs-cache/deps" "$t/keep9" && cd "$t/lockname"
touch "$t/keep9/precious"
printf '[package]\nname = "lockname"\n' > zs.toml
printf '[dependencies]\n../../../keep9 = { git = "file:///nonexistent/x", version = "1.0.0", commit = "0123456789abcdef0123456789abcdef01234567" }\n' > zs.lock
printf 'let main () =\n  0\n' > src/main.zs
"$zs" check src/main.zs 2>&1
[ -f "$t/keep9/precious" ] && echo "../../../keep9 is still there"
grep -c keep9 zs.lock | sed 's/^/zs.lock entries for it: /'

# zs update writes a release's version field itself, not the first "version" on its line (here
# in the URL, …/conversion), and keeps the line's comment
git clone -q "$t/c" "$t/conversion"
mkdir -p "$t/conv/src" && cd "$t/conv"
printf '[package]\nname = "conv"\n\n[dependencies]\nc = { git = "file://%s/conversion", version = "1.1" } # a version from before\n' "$t" > zs.toml
printf 'let main () =\n  println $"c {C.release ()}"\n  0\n' > src/main.zs
"$zs" update 2>/dev/null && grep '^c = ' zs.toml | sed "s|$t|…|"
"$zs" run 2>/dev/null

# a packaged provider (0001) whose own git dependency, helper, is the project's checkout, as the
# project's zs.lock pinned it: the provider's build (a zs build of its own) fetches and locks
# nothing apart, so after helper's main moves on the provider still runs the locked helper
repo helper
printf '[package]\nname = "helper"\nmain = "src/Helper.zs"\n' > "$t/helper/zs.toml"
printf '/// The word.\nlet word () = "locked"\n' > "$t/helper/src/Helper.zs"
release helper 1.0.0
repo gen
printf '[package]\nname = "gen"\nmain = "Main.zs"\n\n[provider]\nmain = "Main.zs"\n\n[dependencies]\nhelper = { git = "file://%s/helper", rev = "main" }\n' "$t" > "$t/gen/zs.toml"
cat > "$t/gen/Main.zs" <<'ZS'
// A provider whose module holds its dependency's word.
let main () =
  println "// provided by gen 0.1"
  println ""
  println $"let word = \"{Helper.word ()}\""
  0
ZS
release gen 1.0.0
mkdir -p "$t/papp/src" && cd "$t/papp"
printf '[package]\nname = "papp"\n\n[dependencies]\ngen = { git = "file://%s/gen", rev = "v1.0.0" }\n' "$t" > zs.toml
cat > src/main.zs <<'ZS'
import gen "words"

let main () =
  println word
  0
ZS
"$zs" run 2>/dev/null
if [ -e .zs-cache/deps/gen/zs.lock ] || [ -e .zs-cache/deps/gen/.zs-cache ]; then echo "gen's provider resolved dependencies of its own"
else echo "gen's provider was built against the project's checkouts"; fi
grep -o '^helper = { git = "[^"]*", rev = "[^"]*"' zs.lock | sed 's/git = "[^"]*", //'
printf '/// The word.\nlet word () = "moved"\n' > "$t/helper/src/Helper.zs"
git -C "$t/helper" -c user.name=zs -c user.email=zs@example.invalid commit -qam moved
rm -rf .zs-cache/providers
"$zs" run 2>/dev/null | sed 's/^/(helper moved on) /'
