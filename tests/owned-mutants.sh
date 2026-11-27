#!/usr/bin/env bash
# The ownership check (Core.Check.owned, zs build --check-ir) catches reference counting that's
# wrong: seven copies of the compiler, each with one mistake put into Opt/Rc.zs (a drop left out,
# a dup left out, a drop before a read, a reuse token not freed, a mutable filled as moved out
# that wasn't), must each be stopped by the check on some program of tests/.
# Heavy (seven builds of the compiler, ten minutes): run alone, by hand, after a change to
# Opt/Rc.zs or to the check; ./test.sh doesn't run it. Its output is tests/owned-mutants.expected.
#   tests/owned-mutants.sh        (in the container: it needs $ZS_STAGE0)
set -u
cd "$(dirname "$0")/.."
[ -x "${ZS_STAGE0:-}" ] || { echo "no stage 0 compiler (\$ZS_STAGE0): run through ./dev"; exit 1; }
root=$PWD; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cat > "$t/mutate.py" <<'PY'
import sys
n = int(sys.argv[1]); p = sys.argv[2]; s = open(p).read()
M = {
  # a dead variable's drop left out
  1: ("      drops dead e3\n", "      e3\n"),
  # a borrowed variable given away without a dup
  2: ("if Set.contains x owned then e else if heap e.ty then mk (CDup(x, e.ty, e)) e.ty else e", "e"),
  # a field under a dying cell used without a dup
  3: ("(p, g2, dups nested (mk node body.ty))", "(p, g2, mk node body.ty)"),
  # a reuse token not freed on the path that builds nothing
  4: ("re (CIf(c, Option.defaultValue (free t) t2, Option.defaultValue (free f) f2))", "re (CIf(c, Option.defaultValue t t2, Option.defaultValue f f2))"),
  # a mutable filled as moved out that wasn't
  5: ("| CCallDirect(g, args) when direct args -> Some(mk (CCallDirect(g, take args)) w.ty)", "| CCallDirect(g, args) when direct args -> Some(mk (CCallDirect(g, args)) w.ty)"),
  # an array dropped before its element is read
  6: ("          re (CLet(r, read, mk (CDrop(x, typeOf x, mk (CLocal r) e.ty)) e.ty))\n        else\n          read", "          mk (CDrop(x, typeOf x, read)) e.ty\n        else\n          read"),
  # a record dropped before the field read from it is dup'ed
  7: ("          let res1 = if Set.contains x owned then mk (CDrop(x, typeOf x, res0)) e.ty else res0\n          let res2 = if heap e.ty then mk (CDup(f, e.ty, res1)) e.ty else res1", "          let res1 = if heap e.ty then mk (CDup(f, e.ty, res0)) e.ty else res0\n          let res2 = if Set.contains x owned then mk (CDrop(x, typeOf x, res1)) e.ty else res1"),
}
a, b = M[n]
if s.count(a) != 1: sys.exit(1)
open(p, "w").write(s.replace(a, b))
PY
programs=$(find tests -name '*.zs' | sort | while read -r p; do [ -f "${p%.zs}.out" ] && echo "$p"; done)
export t
for m in 1 2 3 4 5 6 7; do
  rm -rf "$t/m" "$t/bin" "$t/out"; mkdir -p "$t/m" "$t/out"; cp -r src "$t/m/src"; ln -s "$root/packages" "$t/m/packages"
  python3 "$t/mutate.py" $m "$t/m/src/Opt/Rc.zs" || { echo "mutant $m: Opt/Rc.zs no longer has the line it changes"; continue; }
  ZS_RUNTIME="$root/runtime" ZS_NO_SERVER=1 timeout 900 "$ZS_STAGE0" build "$t/m/src/Main.zs" --release -o "$t/zs" > "$t/build.log" 2>&1 || { echo "mutant $m: didn't build"; continue; }
  src/install.sh "$t/zs" "$t/bin" > /dev/null
  echo "$programs" | xargs -P 8 -I{} bash -c 'ZS_NO_SERVER=1 ZS_CHECK_IR=1 timeout 120 "$t/bin/zs" build {} -o "$t/out/p.$$" > "$t/out/$$.log" 2>&1'
  if grep -q 'check-ir.*after reference counting' "$t"/out/*.log; then echo "mutant $m: caught"; else echo "mutant $m: MISSED"; fi
done
