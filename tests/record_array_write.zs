// An element of an array in a let mutable record's field is written in place: the array is
// taken out of the record for the write and put back, so it's held once (left in the record it
// was held twice, and every write copied it). The value's meaning is an array's: another name
// for the record, or for the array, doesn't see the write.
type Inner = { values: array<int>; label: string }

type Outer = { inner: Inner; counts: array<int> }

let main () =
  let n = 1000
  let mutable r = { inner = { values = Array.create n 0; label = "in" }; counts = Array.create n 1 }
  let before = Runtime.allocations ()
  for i in 0 .. n - 1 do
    r.counts.[i] <- i
    r.inner.values.[i] <- r.counts.[i] * 2
    r.inner.values.[i] += 1
  let made = Runtime.allocations () - before
  println $"{made} {Array.sum r.counts} {Array.sum r.inner.values} {r.inner.label}"
  // shared: the first write copies, once
  let kept = r
  let alone = r.counts
  let before = Runtime.allocations ()
  for i in 0 .. n - 1 do
    r.counts.[i] <- 0
  let made = Runtime.allocations () - before
  println $"{made} {Array.sum r.counts} {Array.sum kept.counts} {Array.sum alone}"
  // the value written may read the array it's written to, and the index is evaluated once
  let calls = ref 0
  let next () =
    calls.Value <- calls.Value + 1
    0
  r.counts.[next ()] <- r.counts.[1] + Array.length r.counts
  println $"{r.counts.[0]} {calls.Value}"
  println $"{r.counts.[n]}"
  0
