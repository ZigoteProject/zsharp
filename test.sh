#!/usr/bin/env bash
# Builds the compiler, then checks every tests/*.zs: run output vs .out, or compile error vs .err.
# --valgrind: also run each program under valgrind (memory errors or leaks fail the test).
set -u
cd "$(dirname "$0")"
dotnet build src -c Release -o bin --nologo -v q || exit 1
export ZS_LEAKCHECK=1 ZS_BACKTRACE=0  # report leaked objects at exit; deterministic panic output
valgrind=0; [ "${1:-}" = "--valgrind" ] && valgrind=1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
for t in tests/*.zs; do
  base=${t%.zs}
  if [ -f "$base.err" ]; then
    actual=$(bin/zs build "$t" -o "$tmp/exe" 2>&1); expected=$(cat "$base.err")
  elif ! bin/zs build "$t" -o "$tmp/exe" 2>"$tmp/build.log"; then
    actual=$(cat "$tmp/build.log"); expected=$(cat "$base.out")
  else
    run=("$tmp/exe")
    # panics abort without cleanup by design, so only exit-normally programs are leak-checked
    [ $valgrind = 1 ] && ! grep -q "^panic:" "$base.out" && run=(valgrind -q --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=99 "$tmp/exe")
    actual=$("${run[@]}" 2>&1); code=$?
    expected=$(cat "$base.out")
    [ $code = 99 ] && actual="$actual
(valgrind reported memory errors or leaks)"
  fi
  if [ "$actual" == "$expected" ]; then echo "ok   $t"
  else echo "FAIL $t"; diff <(echo "$expected") <(echo "$actual") | head -20; fail=1; fi
done
exit $fail
