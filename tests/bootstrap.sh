#!/usr/bin/env bash
# The bootstrap (0020): src/ built --release by the compiler under test (gen 1), by gen 1
# (gen 2) and by gen 2 (gen 3), and gen 3 again with one worker: gen 2 and gen 3 are the same
# bytes, under one worker and under the cores.
set -u
cd "$(dirname "$0")/.."
zs=${1:-bin/zs}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# the library and the runtime of the tree: a generation in a directory of its own has neither
export ZS_NO_SERVER=1 ZS_LIB=$PWD/lib ZS_RUNTIME=$PWD/runtime
build() { # compiler out [VAR=value…]: a release build from an empty cache of its own
  local z=$1 out=$2; shift 2
  env XDG_CACHE_HOME="$t/cache-$(basename "$out")" "$@" "$z" build src/Main.zs --release -o "$out" >/dev/null 2>"$t/err" \
    || { echo "$(basename "$out") doesn't build: $(head -1 "$t/err")"; exit 1; }
}
# each generation's IR kept as it's built: when two binaries differ, the first module whose IR
# differs is named (or their IR doesn't: the difference is clang's or the linker's)
mkdir -p "$t/ir2" "$t/ir3" "$t/ir3w"
build "$zs" "$t/gen1"
build "$t/gen1" "$t/gen2" "ZS_DUMP_IR=$t/ir2"
build "$t/gen2" "$t/gen3" "ZS_DUMP_IR=$t/ir3"
build "$t/gen2" "$t/gen3w" ZS_WORKERS=1 "ZS_DUMP_IR=$t/ir3w"
differ() { # what ir ir
  for f in $(cd "$2" && ls); do
    cmp -s "$2/$f" "$3/$f" || { echo "$1, first in ${f%.ll}"; exit 1; }
  done
  echo "$1, their IR doesn't"
  exit 1
}
cmp -s "$t/gen2" "$t/gen3" && echo "gen 2 = gen 3" || differ "gen 2 and gen 3 differ" "$t/ir2" "$t/ir3"
cmp -s "$t/gen3" "$t/gen3w" && echo "gen 3 = gen 3 with one worker" || differ "one worker makes another gen 3" "$t/ir3" "$t/ir3w"
