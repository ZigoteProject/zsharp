// Arrays are copy-on-write values; Buffer<'a> is the shared mutable alternative.
let fill (a: array<int>) =
  let mutable b = a // a copy only when written while shared
  b.[0] <- 99
  b

// small enough to be inlined: `a <- bump a` must still hand over a's own reference
let bump (a: array<int>) =
  let mutable a = a
  a.[0] <- a.[0] + 1
  a

let main () =
  let a = [| 1; 2; 3 |]
  let mutable b = a
  b.[0] <- 9
  println $"value: a {a.[0]} b {b.[0]}"
  let c = Array.set a 1 7
  println $"Array.set: a {a.[1]} c {c.[1]}"
  let d = fill a
  println $"through a function: a {a.[0]} d {d.[0]}"
  // a unique array is written in place: no allocations in the loop
  let mutable big = Array.create 1000 0
  let before = Runtime.allocations ()
  for i in 0 .. 999 do
    big.[i] <- i * 2
  println $"in place: {Runtime.allocations () - before} allocations, last {big.[999]}"
  let mutable words = [| "x"; "y" |]
  let saved = words
  words.[1] <- words.[0] + "z"
  println $"strings: {saved.[1]} {words.[1]}"
  let buf = Buffer.create 3 0
  let alias = buf
  alias.[0] <- 5
  println $"Buffer: {buf.[0]} length {Buffer.length buf}"
  let snapshot = Buffer.toArray buf
  alias.[0] <- 6
  println $"toArray copies: {snapshot.[0]} {buf.[0]}"
  let mutable counter = Array.create 100 0
  let start = Runtime.allocations ()
  for _ in 1 .. 1000 do
    counter <- bump counter
  println $"inlined update: {Runtime.allocations () - start} allocations, {counter.[0]}"
  0
