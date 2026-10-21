// insertion sort of 512 i32 in place (a let mutable array: copy-on-write stays in place)
let isort (a: array<i32>) =
  let mutable a = a
  for i in 1 .. Array.length a - 1 do
    let v = a.[i]
    let mutable j = i - 1
    while j >= 0 && a.[j] > v do
      a.[j + 1] <- a.[j]
      j <- j - 1
    a.[j + 1] <- v
  a

let main () =
  let mutable a = Array.create 512 (i32 0)
  for i in 0 .. 511 do
    a.[i] <- i32 ((i * 7919) % 1009)
  let t0 = Runtime.ticks ()
  a <- isort a
  let t1 = Runtime.ticks ()
  println $"isort result={a.[0] + a.[255] + a.[511]} ticks={t1 - t0}"
  0
