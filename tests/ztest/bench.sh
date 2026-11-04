#!/usr/bin/env bash
# zs bench (0009, D9): a file's bench values timed, each in its own process, with a median and a
# confidence interval; the results saved beside the file, and the next run compared with them:
# a planted slowdown (four times the work) named, and, with the saved results edited to say so,
# a benchmark far faster than saved, one far slower, and one whose saved interval covers
# anything (nothing said). testFaster is a test that passes when one body is faster with
# statistical confidence.
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
    testFaster "summing 1000 is faster than 50000" (fun () -> List.sum (List.init 1000 (fun i -> i))) (fun () -> List.sum (List.init 50000 (fun i -> i)))
    test "passes" (fun () -> assert (work 10 = 24))
  ]
ZS
}
cd "$t"
strip() { sed -E 's/: [0-9.]+ (ns|µs|ms|s) \[[^]]*\] \([0-9]+ runs\)//; s/slower by [0-9]+% \(was .*\)/slower/; s/faster by [0-9]+% \(was .*\)/faster/'; }
write 20000
echo "first run:"; "$zs" bench perf.zs --runs 20 | strip
# the saved results edited: sum ten times slower than it is, sort ten times faster, as if the
# last build had been
saved=.zs-cache/bench/perf.tsv
awk -F'\t' 'BEGIN{OFS="\t"} $1=="perf/sum"{print $1,$2*10,$3*10,$4*10; next} $1=="perf/sort"{print $1,int($2/10),int($3/10),int($4/10); next} {print}' "$saved" > "$saved.new" && mv "$saved.new" "$saved"
echo "against a saved run ten times slower for sum, ten times faster for sort:"; "$zs" bench perf.zs --runs 20 | strip
# the saved intervals so wide that nothing is beyond them
awk -F'\t' 'BEGIN{OFS="\t"} {print $1,$2,1,1000000000000}' "$saved" > "$saved.new" && mv "$saved.new" "$saved"
echo "against saved intervals that cover anything:"; "$zs" bench perf.zs --runs 20 | strip
write 80000
echo "sum does four times the work:"; "$zs" bench perf.zs sum --runs 20 | strip
echo "zs test runs the benchmarks once, as tests:"; "$zs" test perf.zs | grep -v '^[0-9]* passed'
