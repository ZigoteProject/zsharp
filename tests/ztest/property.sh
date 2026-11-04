#!/usr/bin/env bash
# properties under zs test (0010, step 2): a case that panics is recorded as drawn, shrunk by
# replays of the test binary to a smallest case that still panics, shown, and saved beside the
# file; the next run replays it first, and once the bug is fixed the saved case passes and goes.
# A run that gives up on its discards fails as it is: no one case reproduces it, so nothing is
# shrunk or saved. A shrink keeps the panic it started with: a candidate that fails another way
# (another panic, a stack overflow from values recursing on the zeros past its end) isn't taken
# for it, while one whose panic differs only in its values is.
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
echo "saved:"; (cd .zs-cache/failures && find . -type f | sed 's|^\./||')
echo "again: the saved case first"; "$zs" test evens.zs | sed -E 's/in [0-9]+ runs/in N runs/'
write 200
echo "fixed: the saved case passes and goes"; "$zs" test evens.zs
find .zs-cache/failures -type f 2>/dev/null | wc -l
cat > gives.zs <<'ZS'
open Testing

[<Tests>]
let tests =
  testList "g" [
    testPropertyWith { seed = Some (u64 2) } "never holds" (fun () ->
      prop {
        let! n = Gen.int ()
        do! Prop.assume (n > 1000000)
        return true
      })
  ]
ZS
echo "a run that gives up on its discards fails, unshrunk:"; "$zs" test gives.zs; echo "exit $?"
find .zs-cache/failures -type f 2>/dev/null | wc -l
cat > deep.zs <<'ZS'
open Testing

[<Derive(Arbitrary)>]
type T =
  | A of result<T, int>
  | B of list<T> * int

let rec biggest (t: T) : int =
  match t with
  | A(Ok x) -> biggest x
  | A(Error n) -> n
  | B(xs, n) -> List.fold (fun m x -> max m (biggest x)) n xs

[<Tests>]
let tests =
  testList "d" [
    testPropertyWith { seed = Some (u64 2) } "small numbers" (fun (t: T) -> if biggest t > 5 then panic "a big number")
  ]
ZS
echo "shrunk to the same panic:"; "$zs" test deep.zs | sed -E 's/from [0-9]+ bytes to [0-9]+ in [0-9]+ runs/from N bytes to M in N runs/; s/-[0-9a-f]{8},/-HASH,/'
cat > two.zs <<'ZS'
open Testing

// two bugs: the third element not 0 panics with its value, and 0 there reads past an array
let probe (xs: list<int>) : unit =
  if List.length xs >= 3 then
    let i = List.item 2 xs
    if i <> 0 then panic $"the third is {i}"
    else ignore ([| 1; 2 |].[i + 7])

[<Tests>]
let tests =
  testList "s" [
    testPropertyWith { seed = Some (u64 5) } "short lists" (fun (xs: list<int>) -> probe xs)
  ]
ZS
echo "shrunk within its own bug:"; "$zs" test two.zs | sed -E 's/from [0-9]+ bytes to [0-9]+ in [0-9]+ runs/from N bytes to M in N runs/; s/-[0-9a-f]{8},/-HASH,/'
cat > digits.zs <<'ZS'
open Testing

// two bugs whose panics start with their values
let probe (xs: list<int>) : unit =
  if List.length xs >= 3 then
    let i = List.item 2 xs
    if i <> 0 then panic $"{i} is the third" else panic $"{List.length xs} long, a zero third"

[<Tests>]
let tests =
  testList "d" [
    testPropertyWith { seed = Some (u64 5) } "short lists" (fun (xs: list<int>) -> probe xs)
  ]
ZS
echo "kept apart though their panics start with numbers:"; "$zs" test digits.zs | sed -E 's/from [0-9]+ bytes to [0-9]+ in [0-9]+ runs/from N bytes to M in N runs/; s/-[0-9a-f]{8},/-HASH,/'
cat > flags.zs <<'ZS'
open Testing

// a panic that shows the value: words (true, false) shrink as numbers do
let probe (flags: list<bool>) : unit = if List.length flags >= 3 then panic $"too many flags: {flags}"

[<Tests>]
let tests =
  testList "b" [
    testPropertyWith { seed = Some (u64 3) } "few flags" (fun (flags: list<bool>) -> probe flags)
  ]
ZS
echo "a shown value shrinks:"; "$zs" test flags.zs | sed -E 's/from [0-9]+ bytes to [0-9]+ in [0-9]+ runs/from N bytes to M in N runs/; s/-[0-9a-f]{8},/-HASH,/'
cat > caps.zs <<'ZS'
open Testing

// two bugs whose messages differ by a capitalized word, which is the message's, not a value
let probe (xs: list<int>) : unit =
  if List.length xs >= 3 then
    if List.item 2 xs <> 0 then panic "bad order after Insert" else panic "bad order after Remove"

[<Tests>]
let tests =
  testList "c" [
    testPropertyWith { seed = Some (u64 5) } "order" (fun (xs: list<int>) -> probe xs)
  ]
ZS
echo "kept apart by a word of the message:"; "$zs" test caps.zs | sed -E 's/from [0-9]+ bytes to [0-9]+ in [0-9]+ runs/from N bytes to M in N runs/; s/-[0-9a-f]{8},/-HASH,/'
