#!/usr/bin/env bash
# The bootstrap (0020): src/ built --release by the compiler under test (gen 1), by gen 1
# (gen 2) and by gen 2 (gen 3), and gen 3 again with one worker: gen 2 and gen 3 are the same
# bytes, under one worker and under the cores. When they differ, the first module whose IR
# differs is named (ZS_DUMP_IR of both).
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
build "$zs" "$t/gen1"
build "$t/gen1" "$t/gen2"
build "$t/gen2" "$t/gen3"
build "$t/gen2" "$t/gen3w" ZS_WORKERS=1
if cmp -s "$t/gen2" "$t/gen3"; then
  echo "gen 2 = gen 3"
else
  mkdir -p "$t/ir2" "$t/ir3"
  build "$t/gen1" "$t/ir2/zs" "ZS_DUMP_IR=$t/ir2"
  build "$t/gen2" "$t/ir3/zs" "ZS_DUMP_IR=$t/ir3"
  for f in $(cd "$t/ir2" && ls *.ll); do
    cmp -s "$t/ir2/$f" "$t/ir3/$f" || { echo "gen 2 and gen 3 differ, first in ${f%.ll}"; exit 1; }
  done
  echo "gen 2 and gen 3 differ, their IR doesn't"
  exit 1
fi
cmp -s "$t/gen3" "$t/gen3w" && echo "gen 3 = gen 3 with one worker" || { echo "one worker makes another gen 3"; exit 1; }
