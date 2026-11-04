#!/usr/bin/env bash
# zs test --coverage (D10): a counter per line of the test's files, each test's process writing
# them at exit; the lines run and not run per file, and coverage.lcov for genhtml. The branches
# no test reaches are reported by their lines; the library's lines aren't counted.
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cat > "$t/cov.zs" <<'ZS'
open Testing

let classify (n: int) =
  if n < 0 then
    "negative"
  else if n = 0 then
    "zero"
  else
    "positive"

let rec count (xs: list<int>) =
  match xs with
  | [] -> 0
  | _ :: rest -> 1 + count rest

let unused () =
  println "never"
  1

[<Tests>]
let tests =
  testList "cov" [
    test "positive" (fun () -> assert (classify 3 = "positive"))
    test "count" (fun () -> assert (count [ 1; 2 ] = 2))
  ]
ZS
cd "$t"
"$zs" test cov.zs --coverage
echo "lcov:"
grep -c '^DA:' coverage.lcov
grep '^SF:' coverage.lcov | sed "s|$t/||"
echo "a program that ends with Environment.exit writes its counts too:"
cat > ex.zs <<'ZS'
let check n =
  if n > 3 then
    println "big"
    Environment.exit 2
  n

let main () =
  println $"{check 5}"
  0
ZS
"$zs" build --coverage ex.zs -o ex && ./ex; echo "exit $?"; [ -s ex.zscov ] && echo "ex.zscov written"

echo "a generic function of another module counts as run where an instance of it runs:"
mkdir multi && cd multi
cat > stats.zs <<'ZS'
let largest (xs: list<'a>) : 'a =
  List.reduce max xs

let smallest (xs: list<'a>) : 'a =
  List.reduce min xs
ZS
cat > main.zs <<'ZS'
open Testing
open Stats

[<Tests>]
let tests =
  testList "stats" [
    test "largest" (fun () -> assert (largest [ 3; 9; 4 ] = 9))
  ]
ZS
"$zs" test main.zs --coverage | grep "stats.zs"
echo "threads that all end the program at once write the counts once:"
cd ..
cat > race.zs <<'ZS'
open Threading

let main () =
  let n = Parallel.workers ()
  let arrived = Atomic.make 0
  Parallel.for 0 n (fun i ->
    Atomic.add arrived 1 |> ignore
    while Atomic.get arrived < n do
      ()
    Environment.exit 3)
  0
ZS
"$zs" build --coverage race.zs -o race
dups=0
for i in 1 2 3 4 5 6 7 8; do
  rm -f race.zscov
  ZS_WORKERS=4 timeout 20 ./race
  [ -s race.zscov ] && [ "$(sort race.zscov | uniq -d | wc -l)" = 0 ] || dups=$((dups + 1))
done
echo "runs with a copy too many or none: $dups"
