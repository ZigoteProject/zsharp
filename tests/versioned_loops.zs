// Loop versioning: a for loop whose array reads and writes are in bounds and whose arithmetic over
// x doesn't overflow for its whole range runs a copy without those checks, any other the checked
// one, and both must do the same: writes with x, x - c and c - x, an index without x read and
// written each time, a shared array the first write copies (with its length), an empty loop whose
// index is never checked, a 2D index, % and / by constants (of numbers below 0 too), a product
// whose range is wider than its values, and one whose range overflows where it isn't computed
let main () =
  let n = 8
  let mutable a = Array.create n 0
  for i in 0 .. n - 1 do
    a.[i] <- i * 10
  for i in 1 .. n - 1 do
    a.[i] <- a.[i] + a.[i - 1]
  let mutable b = Array.create n 0
  for i in 0 .. n - 1 do
    b.[n - 1 - i] <- a.[i]
  println $"{Array.toList a} {Array.toList b}"
  let k = 3
  let mutable total = Array.create 1 0
  for i in 0 .. n - 1 do
    total.[0] <- total.[0] + a.[k] + i
  println $"{total.[0]}"
  let shared = a
  let mutable c = shared
  for i in 0 .. n - 1 do
    c.[i] <- -c.[i]
  println $"{shared.[1]} {c.[1]}"
  for i in 5 .. 4 do
    a.[100] <- i
  // one write in bounds and one past the end: the checked copy runs
  let mutable d = Array.create 4 0
  let mutable e = Array.create 3 0
  for i in 0 .. 3 do
    d.[i] <- i
    if i < 3 then e.[i] <- i
  println $"{Array.toList d} {Array.toList e}"
  let w = 4
  let mutable grid = Array.create (w * w) 0
  for r in 0 .. w - 1 do
    for c in 0 .. w - 1 do
      grid.[r * w + c] <- r * 10 + c
  let mutable ring = Array.create 5 0
  for j in 0 .. 11 do
    ring.[(j + 3) % 5] <- ring.[(j + 3) % 5] + j / 2
  let mutable neg = Array.create 8 0
  for j in 0 .. 7 do
    neg.[j] <- (j - 3) % 5 + 1
  let mutable sq = Array.create 26 0
  for j in 0 .. 10 do
    sq.[(j - 5) * (j - 5)] <- j
  let huge = 4611686018427387904
  let mutable once = Array.create 3 0
  for j in 0 .. 2 do
    once.[j] <- if j = 0 then j * huge else j
  println $"{Array.toList grid}"
  println $"{Array.toList ring} {Array.toList neg} {Array.toList sq} {Array.toList once}"
  0
