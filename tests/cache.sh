#!/usr/bin/env bash
# What builds keep between them (in the cache directory): the checked library and a program's
# modules (Driver: the type checker's state, saved under a hash of their sources), and the
# compiled LLVM module of each source file (saved under a hash of its IR). A build from the
# cache must be the same program as one without it, a changed file must be seen, and only the
# modules whose IR changed are compiled again.
set -u
cd "$(dirname "$0")/.."
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export XDG_CACHE_HOME=$t/cache
cp tests/modules/main.zs tests/modules/geometry.zs tests/modules/units.zs "$t/"
# zs build --time names how many objects it compiled: the runtime's and one per source file
built() { bin/zs build "$t/main.zs" -o "$t/exe" --time 2>&1 | grep -o 'clang ([0-9]* of [0-9]* new)'; echo "  runs: $("$t/exe" | tr '\n' ' ')"; }
ZS_NO_CACHE=1 bin/zs build "$t/main.zs" -o "$t/a" --emit-llvm
echo "without the cache: $("$t/a" | tr '\n' ' ')"
bin/zs build "$t/main.zs" -o "$t/b" --emit-llvm
echo "states saved: $(ls "$t/cache/zs/checked" | wc -l)" # the library's, and with the modules
bin/zs build "$t/main.zs" -o "$t/c" --emit-llvm
cmp -s "$t/a.ll" "$t/c.ll" && echo "from the cache: the same program"
echo "first build:"; built
echo "again:"; built
# a changed module: checked again (from the library's state), and its change is in the program
sed -i 's/pi () \* r \* r/2.0 * pi () * r * r/' "$t/geometry.zs"
echo "a module changed:"; built
echo "states saved: $(ls "$t/cache/zs/checked" | wc -l)"
# a changed main file: the modules come from the cache
sed -i 's/Circle 2.0/Circle 1.0/' "$t/main.zs"
echo "the main file changed:"; built
# an unreadable state is ignored: built as without the cache
for f in "$t"/cache/zs/checked/*.bin; do head -c 100 "$f" > "$f.cut" && mv "$f.cut" "$f"; done
bin/zs build "$t/main.zs" -o "$t/f" && echo "unreadable states: $("$t/f" | tr '\n' ' ')"
