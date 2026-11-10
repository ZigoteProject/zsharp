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
# an edit in place, as GNU's sed and BSD's (macOS's) both take it
edit() { sed "$1" "$2" > "$2.new" && mv "$2.new" "$2"; }
# binaries compared have one name, each in a directory of its own: macOS's ad-hoc signature holds
# the binary's name
mkdir -p "$t/ref" "$t/fresh" "$t/c1" "$t/c2"
# zs build --time names the program's modules it checked, how many LLVM modules came from the
# module cache, and how many objects it compiled (the runtime's, and two per source file: its own
# functions and its copies of the library's); the binary must be the one a build without the
# cache makes (ZS_NO_CACHE=1: only what's kept under a hash of its contents is used)
built() {
  bin/zs build "$t/main.zs" -o "$t/exe" --time 2>&1 | grep -oE 'program: [^)]*|module cache \([0-9]* of [0-9]*\)|clang \([0-9]* of [0-9]* new\)' | paste -sd ' ' -
  ZS_NO_CACHE=1 XDG_CACHE_HOME=$t/ref bin/zs build "$t/main.zs" -o "$t/ref/exe" && cmp -s "$t/exe" "$t/ref/exe" || echo "  a different binary than without the cache"
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
edit 's/pi () \* r \* r/2.0 * pi () * r * r/' "$t/geometry.zs"
echo "a body changed in geometry.zs:"; built
# an annotation that doesn't change a type: the interface is the same
edit 's/^let describe s =/let describe (s: Shape) =/' "$t/geometry.zs"
echo "an annotation in geometry.zs:"; built
# a new function changes geometry.zs's interface: main.zs uses it, units.zs doesn't
printf '\nlet perimeter s =\n  match s with\n  | Circle r -> 6.0 * r\n  | Square a -> 4.0 * a\n' >> "$t/geometry.zs"
echo "geometry.zs's interface changed:"; built
# units.zs is used by both
edit 's/"area:"/"area =>"/' "$t/units.zs"
echo "a body changed in units.zs:"; built
edit 's/^let label () =/let label (): string =/' "$t/units.zs"
printf '\nlet unit () = "m"\n' >> "$t/units.zs"
echo "units.zs's interface changed:"; built
edit 's/Circle 2.0/Circle 1.0/' "$t/main.zs"
echo "the main file changed:"; built
# after the edits, the same binary as from an empty cache
XDG_CACHE_HOME=$t/empty bin/zs build "$t/main.zs" -o "$t/fresh/exe" && cmp -s "$t/exe" "$t/fresh/exe" && echo "after the edits: the same binary as from an empty cache"
# an unreadable result is ignored: checked again
for f in "$t"/cache/zs/checked/*.bin; do head -c 100 "$f" > "$f.cut" && mv "$f.cut" "$f"; done
bin/zs build "$t/main.zs" -o "$t/f" && echo "unreadable results: $("$t/f" | tr '\n' ' ')"
# the object cache of a host build's module per file: Windows' builds are one module and keep
# none, so these two checks are left out there (test.sh drops their lines from cache.expected)
if [ -d "$t/cache/zs/objects" ]; then
  # a module's IR is compiled from a file of this build's own: one another build writes and
  # deletes at the same time, at the name the object's key gives, is no matter (here a directory
  # there)
  rm -rf "$t/cache/zs/modules"
  for o in "$t"/cache/zs/objects/*.o; do mkdir "${o%.o}.ll"; done
  rm -f "$t"/cache/zs/objects/*.o
  bin/zs build "$t/main.zs" -o "$t/g" && echo "beside another build's IR: $("$t/g" | tr '\n' ' ')"
  rmdir "$t"/cache/zs/objects/*.ll
  # what a build stopped while clang ran leaves (its IR, a depfile) is removed an hour on, not
  # before
  touch -t 200001010000 "$t/cache/zs/objects/old.o.zs-1.ll" "$t/cache/zs/objects/old.o.zs-1.o.d"
  touch "$t/cache/zs/objects/new.o.zs-2.ll"
  bin/zs build "$t/main.zs" -o "$t/g" && echo "a stopped build's files kept: $(cd "$t/cache/zs/objects" && ls old.* new.* 2>/dev/null | tr '\n' ' ')"
  rm -f "$t/cache/zs/objects/new.o.zs-2.ll"
fi
# a package's C source is kept under a key of every header it includes, not only those beside it:
# one in the package's include directory changed is a new object, as it is a new import c
mkdir -p "$t/geo/src" "$t/geo/c/src" "$t/geo/c/include"
printf '[package]\nname = "geo"\n\n[c]\nsources = ["c/src/geo.c"]\ninclude = ["c/include"]\n' > "$t/geo/zs.toml"
printf '#define GEO_SCALE 2\nint geo_scale(void);\n' > "$t/geo/c/include/geo.h"
printf '#include "geo.h"\n\nint geo_scale(void) { return GEO_SCALE; }\n' > "$t/geo/c/src/geo.c"
printf 'import c "geo.h"\n\nlet main () =\n  println $"scale {geo_scale ()} {GEO_SCALE}"\n  0\n' > "$t/geo/src/main.zs"
bin/zs build "$t/geo/src/main.zs" -o "$t/geo/exe" && echo "a package's C: $("$t/geo/exe")"
edit 's/GEO_SCALE 2/GEO_SCALE 3/' "$t/geo/c/include/geo.h"
bin/zs build "$t/geo/src/main.zs" -o "$t/geo/exe" && echo "its header changed in its include directory: $("$t/geo/exe")"
# a header added beside it, which its #include "geo.h" finds first: a new object too (import c
# still finds the include directory's)
printf '#define GEO_SCALE 4\nint geo_scale(void);\n' > "$t/geo/c/src/geo.h"
bin/zs build "$t/geo/src/main.zs" -o "$t/geo/exe" && echo "a header added beside it: $("$t/geo/exe")"
# a C function one module declares and another calls bare, without naming the first: its
# signature changed, the caller is checked again (and fails), not restored
mkdir -p "$t/ext"
printf 'extern abs : c_int -> c_int\n\nlet ready () = 0\n' > "$t/ext/ffi.zs"
printf 'let run () = int (abs (c_int (-3)))\n' > "$t/ext/calls.zs"
printf 'let main () =\n  let a = Ffi.ready ()\n  let b = Calls.run ()\n  println $"{a} {b}"\n  0\n' > "$t/ext/main.zs"
bin/zs build "$t/ext/main.zs" -o "$t/ext/exe" && echo "a C function called bare: $("$t/ext/exe")"
edit 's/c_int -> c_int/c_int -> c_int -> c_int/' "$t/ext/ffi.zs"
echo "its signature changed: $(bin/zs build "$t/ext/main.zs" -o "$t/ext/exe" 2>&1 | grep -o 'error: .*' | head -1)"
# every test program: a build that restores what the cache has (the library's results, others'
# code) makes the binary a build of everything from nothing makes
differ=""
for p in $(find tests -name '*.zs' | sort); do
  base=${p%.zs}
  [ -f "$base.out" ] || continue
  bin/zs build "$p" -o "$t/c1/exe" >/dev/null 2>&1 || continue
  ZS_NO_CACHE=1 XDG_CACHE_HOME=$t/ref bin/zs build "$p" -o "$t/c2/exe" >/dev/null 2>&1 && cmp -s "$t/c1/exe" "$t/c2/exe" || differ="$differ $p"
done
[ -z "$differ" ] && echo "every test program from the cache: the same binary as from nothing" || echo "from the cache, a different binary:$differ"
