#!/usr/bin/env bash
# zs bench (0009, D9): a file's bench values timed, each in its own process, with a median and a
# confidence interval; the results saved beside the file, and the next run reporting a change
# beyond the noise: nothing for the same build, a planted slowdown (four times the work) named.
# testFaster is a test that passes when one body is faster with statistical confidence.
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
write() {
cat > "$t/perf.zs" <<ZS
open Testing

let work (n: int) = List.sum (List.init n (fun i -> i % 7))

[<Tests>]
let tests =
  testList "perf" [
    bench "sum" (fun () -> work $1)
    bench "sort" (fun () -> List.sort (List.init 2000 (fun i -> (i * 7919) % 1000)))
    testFaster "an int is faster than a float sum" (fun () -> List.sum (List.init 20000 (fun i -> i))) (fun () -> List.sum (List.init 20000 (fun i -> float i * 1.5)))
    test "passes" (fun () -> assert (work 10 = 24))
  ]
ZS
}
cd "$t"
strip() { sed -E 's/: [0-9.]+ (ns|µs|ms|s) \[[^]]*\] \([0-9]+ runs\)//; s/slower by [0-9]+% \(was .*\)/slower/; s/faster by [0-9]+% \(was .*\)/faster/'; }
write 20000
echo "first run:"; "$zs" bench perf.zs --runs 40 | strip
echo "same build:"; "$zs" bench perf.zs --runs 40 | strip
write 80000
echo "sum does four times the work:"; "$zs" bench perf.zs sum --runs 40 | strip
echo "zs test runs the benchmarks once, as tests:"; "$zs" test perf.zs | grep -v '^[0-9]* passed'
