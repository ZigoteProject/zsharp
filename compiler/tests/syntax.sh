#!/usr/bin/env bash
# zs check in Z# on the tests whose mistakes are in their syntax: the first error is the .err
# file's (an error the F# compiler gives no column has one here: it's compared without it).
set -u
zs=${1:-compiler/build/zs}
total=0; bad=0
for f in tests/err_and.zs tests/err_operator_builtin.zs tests/newcomer/{try_with,class,mutable_field,increment,return_braces}.zs; do
  total=$((total + 1))
  want=$(head -1 "${f%.zs}.err")
  got=$("$zs" check "$f" 2>&1 | grep -m1 ': error: ')
  # file:line: error: … against file:line:col: error: …
  if [[ "$want" =~ ^[^:]*:[0-9]+:\ error: ]]; then
    got=$(echo "$got" | sed -E 's/^([^:]*:[0-9]+):[0-9]+: error:/\1: error:/')
  fi
  if [ "$got" != "$want" ]; then bad=$((bad + 1)); echo "$f: want: $want"; echo "$f:  got: $got"; fi
done
echo "$((total - bad)) of $total syntax tests give the same first error"
