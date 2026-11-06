#!/usr/bin/env bash
# src/install.sh, on a copy of the checkout's layout: the paths it's given are the caller's, a
# directory whose lib/ or wepoll/ is something else (a prefix's) or the checkout itself is refused
# with nothing deleted, and a binary that isn't there fails it, the install before kept. Prints
# each run's refusal, its exit code, and what's left.
set -u
cd "$(dirname "$0")/.."
t=$(cd "$(mktemp -d)" && pwd -P); trap 'rm -rf "$t"' EXIT  # resolved, as the script names it
mkdir -p "$t/zsharp/src" "$t/work"
cp src/install.sh "$t/zsharp/src/"
cp -r lib runtime "$t/zsharp/"
# the script from $t/work, its own messages (not cp's, which differ between systems), its exit code
run() {
  (cd "$t/work" && "$t/zsharp/src/install.sh" "$@") 2>"$t/err"
  local code=$?
  grep '^install.sh:' "$t/err" | sed "s|$t|…|g"
  echo "exit $code"
}
cd "$t/work"
echo NEW > zs-new

echo "--- relative paths, from another directory"
run ./zs-new out
echo "out/zs: $(cat out/zs)"
[ -f out/lib/prelude.zs ] && [ -f out/wepoll/wepoll.c ] && [ -f out/rt.c ] && echo "out: the library and the runtime"
[ -e "$t/zsharp/out" ] && echo "the checkout's out: there" || echo "the checkout's out: none"

echo "--- again, over that install"
touch out/lib/stale.zs
run ./zs-new out
[ -e out/lib/stale.zs ] && echo "out/lib: merged" || echo "out/lib: replaced"

echo "--- a binary that isn't there"
echo OLD > out/zs
run ./missing out
echo "out/zs: $(cat out/zs)"

echo "--- a prefix's directory"
mkdir -p prefix/lib && touch prefix/lib/libfoo.so
run ./zs-new prefix
echo "prefix/lib: $(ls prefix/lib)"
[ -e prefix/zs ] && echo "prefix/zs: there" || echo "prefix/zs: none"
mkdir -p other/wepoll && touch other/wepoll/notes.txt
run ./zs-new other
echo "other/wepoll: $(ls other/wepoll)"

echo "--- the checkout"
run ./zs-new ../zsharp
run ./zs-new ../zsharp/lib/zs
[ -f "$t/zsharp/lib/prelude.zs" ] && echo "the checkout's lib: kept"
[ -e "$t/zsharp/zs" ] && echo "the checkout's zs: there" || echo "the checkout's zs: none"
