#!/usr/bin/env bash
# The bootstrap (0020): src/ built --release by the compiler under test (gen 1), by gen 1
# (gen 2) and by gen 2 (gen 3), and gen 3 again with one worker: gen 2 and gen 3 are the same
# bytes, under one worker and under the cores.
set -u
cd "$(dirname "$0")/.."
zs=${1:-bin/zs}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# every generation builds one copy of the tree, taken now: an edit meanwhile (another session's,
# once: the one worker's gen 3, built last, compiled it) can't make two generations differ
mkdir "$t/tree" && cp -r src packages lib runtime "$t/tree/"
# the copy's library and runtime: a generation in a directory of its own has neither
export ZS_NO_SERVER=1 ZS_LIB=$t/tree/lib ZS_RUNTIME=$t/tree/runtime
# zig's cache, for the C library it builds for a target, is one for every generation: a PE's
# timestamp is a hash of what zig linked, its cache's paths included
export ZIG_GLOBAL_CACHE_DIR=$t/zig-cache
# each generation is zs in a directory of its own: the binary may hold its own name (macOS's
# ad-hoc signature, a Windows build's .pdb), the same in every generation
build() { # compiler generation [VAR=value…]: a release build from an empty cache of its own
  local z=$1 gen=$2; shift 2
  mkdir -p "$t/$gen"
  env XDG_CACHE_HOME="$t/cache-$gen" "$@" "$z" build "$t/tree/src/Main.zs" --release -o "$t/$gen/zs" >/dev/null 2>"$t/err" \
    || { echo "$gen doesn't build: $(head -1 "$t/err")"; exit 1; }
}
# each generation's IR kept as it's built: when two binaries differ, the first module whose IR
# differs is named (or their IR doesn't: the difference is clang's or the linker's)
mkdir -p "$t/ir2" "$t/ir3" "$t/ir3w"
build "$zs" gen1
build "$t/gen1/zs" gen2 "ZS_DUMP_IR=$t/ir2"
build "$t/gen2/zs" gen3 "ZS_DUMP_IR=$t/ir3"
build "$t/gen2/zs" gen3w ZS_WORKERS=1 "ZS_DUMP_IR=$t/ir3w"
differ() { # what ir ir
  for f in $(cd "$2" && ls); do
    cmp -s "$2/$f" "$3/$f" || { echo "$1, first in ${f%.ll}"; exit 1; }
  done
  echo "$1, their IR doesn't"
  exit 1
}
cmp -s "$t/gen2/zs" "$t/gen3/zs" && echo "gen 2 = gen 3" || differ "gen 2 and gen 3 differ" "$t/ir2" "$t/ir3"
cmp -s "$t/gen3/zs" "$t/gen3w/zs" && echo "gen 3 = gen 3 with one worker" || differ "one worker makes another gen 3" "$t/ir3" "$t/ir3w"
