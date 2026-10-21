#!/usr/bin/env bash
# Builds the compiler, then checks every tests/*.zs: run output vs .out, or compile error vs .err
set -u
cd "$(dirname "$0")"
dotnet build src -c Release -o bin --nologo -v q || exit 1
export ZS_LEAKCHECK=1 ZS_BACKTRACE=0  # report leaked objects at exit; deterministic panic output
fail=0
for t in tests/*.zs; do
  base=${t%.zs}
  if [ -f "$base.err" ]; then
    actual=$(bin/zs build "$t" 2>&1); expected=$(cat "$base.err")
  else
    actual=$(bin/zs run "$t" 2>&1); expected=$(cat "$base.out")
  fi
  if [ "$actual" == "$expected" ]; then echo "ok   $t"
  else echo "FAIL $t"; diff <(echo "$expected") <(echo "$actual"); fail=1; fi
done
exit $fail
