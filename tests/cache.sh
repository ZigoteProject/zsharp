#!/usr/bin/env bash
# What builds keep between them (in the cache directory): each module's checked result (Driver:
# what checking it added, saved under a key of its source and of what it sees of the modules
# before it), and the compiled LLVM module of each source file (saved under a hash of its IR,
# and under a key of what its code is made from, so an unchanged module isn't even generated).
# A build from the cache must be the same program as one without it, a changed file must be
# seen, and only the modules a change reaches are checked and compiled again.
set -u
cd "$(dirname "$0")/.."
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export XDG_CACHE_HOME=$t/cache
cp tests/modules/main.zs tests/modules/geometry.zs tests/modules/units.zs "$t/"
# zs build --time names the program's modules it checked, how many LLVM modules came from the
# module cache, and how many objects it compiled (the runtime's, and two per source file: its own
# functions and its copies of the library's); the binary must be the one a build without the
# cache makes (ZS_NO_CACHE=1: only what's kept under a hash of its contents is used)
built() {
  bin/zs build "$t/main.zs" -o "$t/exe" --time 2>&1 | grep -o 'program: [^)]*\|module cache ([0-9]* of [0-9]*)\|clang ([0-9]* of [0-9]* new)' | paste -sd ' '
  ZS_NO_CACHE=1 XDG_CACHE_HOME=$t/ref bin/zs build "$t/main.zs" -o "$t/ref-exe" && cmp -s "$t/exe" "$t/ref-exe" || echo "  a different binary than without the cache"
  echo "  runs: $("$t/exe" | tr '\n' ' ')"
}
ZS_NO_CACHE=1 bin/zs build "$t/main.zs" -o "$t/a" --emit-llvm
echo "without the cache: $("$t/a" | tr '\n' ' ')"
bin/zs build "$t/main.zs" -o "$t/b" --emit-llvm
bin/zs build "$t/main.zs" -o "$t/c" --emit-llvm
cmp -s "$t/a.ll" "$t/c.ll" && echo "from the cache: the same program"
echo "first build:"; built
echo "again:"; built
# a function's body changed: only its module is checked again (and compiled)
sed -i 's/pi () \* r \* r/2.0 * pi () * r * r/' "$t/geometry.zs"
echo "a body changed in geometry.zs:"; built
# an annotation that doesn't change a type: the interface is the same
sed -i 's/^let describe s =/let describe (s: Shape) =/' "$t/geometry.zs"
echo "an annotation in geometry.zs:"; built
# a new function changes geometry.zs's interface: main.zs uses it, units.zs doesn't
printf '\nlet perimeter s =\n  match s with\n  | Circle r -> 6.0 * r\n  | Square a -> 4.0 * a\n' >> "$t/geometry.zs"
echo "geometry.zs's interface changed:"; built
# units.zs is used by both
sed -i 's/"area:"/"area =>"/' "$t/units.zs"
echo "a body changed in units.zs:"; built
sed -i 's/^let label () =/let label (): string =/' "$t/units.zs"
printf '\nlet unit () = "m"\n' >> "$t/units.zs"
echo "units.zs's interface changed:"; built
sed -i 's/Circle 2.0/Circle 1.0/' "$t/main.zs"
echo "the main file changed:"; built
# after the edits, the same binary as from an empty cache
cp "$t/exe" "$t/edited"
XDG_CACHE_HOME=$t/empty bin/zs build "$t/main.zs" -o "$t/fresh" && cmp -s "$t/edited" "$t/fresh" && echo "after the edits: the same binary as from an empty cache"
# an unreadable result is ignored: checked again
for f in "$t"/cache/zs/checked/*.bin; do head -c 100 "$f" > "$f.cut" && mv "$f.cut" "$f"; done
bin/zs build "$t/main.zs" -o "$t/f" && echo "unreadable results: $("$t/f" | tr '\n' ' ')"
# every test program: a build that restores what the cache has (the library's results, others'
# code) makes the binary a build of everything from nothing makes
differ=""
for p in $(find tests -name '*.zs' | sort); do
  base=${p%.zs}
  [ -f "$base.out" ] || continue
  bin/zs build "$p" -o "$t/cached" >/dev/null 2>&1 || continue
  ZS_NO_CACHE=1 XDG_CACHE_HOME=$t/ref bin/zs build "$p" -o "$t/fresh" >/dev/null 2>&1 && cmp -s "$t/cached" "$t/fresh" || differ="$differ $p"
done
[ -z "$differ" ] && echo "every test program from the cache: the same binary as from nothing" || echo "from the cache, a different binary:$differ"
