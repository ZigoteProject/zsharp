#!/usr/bin/env bash
# properties under zs test (0010, step 2): a case that panics is recorded as drawn, shrunk by
# replays of the test binary to a smallest case that still panics, shown, and saved beside the
# file; the next run replays it first, and once the bug is fixed the saved case passes and goes.
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
write() {
cat > "$t/evens.zs" <<ZS
open Testing

[<Tests>]
let tests =
  testList "p" [
    testPropertyWith { seed = Some (u64 1) } "evens stay small" (fun (n: int) -> assert (n % 2 = 1 || n < $1))
  ]
ZS
}
cd "$t"
export ZS_BACKTRACE=0
write 20
echo "a planted bug: even numbers from 20 fail the assertion"; "$zs" test evens.zs | sed -E 's/in [0-9]+ runs/in N runs/'
echo "saved:"; ls .zs-cache/failures
echo "again: the saved case first"; "$zs" test evens.zs | sed -E 's/in [0-9]+ runs/in N runs/'
write 200
echo "fixed: the saved case passes and goes"; "$zs" test evens.zs
ls .zs-cache/failures 2>/dev/null | wc -l
