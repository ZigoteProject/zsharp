// x <- f … (reads of x) … x: the call gets x's own reference however the other arguments read x,
// so copy-on-write updates in place (each update used to copy the whole map or array)
let bump (a: array<int>) (i: int) (x: int) =
  let mutable b = a
  b.[i] <- x
  b

let keep (a: array<int>) (i: int) (x: int) = (Array.set a i x, a)

let main () =
  // a read in an earlier argument, as an inlined HashMap.count or tryFind is
  let mutable m = HashMap.empty
  let mark = Runtime.allocations ()
  for i in 1 .. 2000 do
    m <- HashMap.add (i % 100) (Option.defaultValue 0 (HashMap.tryFind (i % 100) m) + 1) m
  let viaRead = Runtime.allocations () - mark
  let mutable h = HashMap.empty
  let mark2 = Runtime.allocations ()
  for i in 1 .. 2000 do
    let seen = Option.defaultValue 0 (HashMap.tryFind (i % 100) h)
    h <- HashMap.add (i % 100) (seen + 1) h
  let hoisted = Runtime.allocations () - mark2
  println $"map: {HashMap.count m} keys, {HashMap.tryFind 7 m}, as many allocations as the hoisted read: {viaRead = hoisted}"
  // arrays: a read in a later argument, then an inlined call whose argument reads the array
  let mutable a = Array.create 100 0
  let mark3 = Runtime.allocations ()
  for i in 0 .. 999 do
    a <- Array.set a (i % 100) (a.[i % 100] + 1)
    a <- bump a (i % 100) (a.[i % 100] * 2)
  println $"array: {Array.sum a}, allocations {Runtime.allocations () - mark3}"
  // a reference the call keeps makes it copy: the kept array is the old one
  let mutable c = Array.create 4 0
  let (c2, old) = keep c 0 5
  c <- c2
  println $"kept {old.[0]}, new {c.[0]}"
  0
