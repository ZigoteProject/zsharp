// A function a call makes crosses threads when the call says it's a share<…> (the lambda it
// returns is checked there), and a top-level function given some of its arguments when what it's
// given is Share.
let adder (n: int) : share<int -> int> = fun i -> i + n

let scale (k: int) (i: int) = k * i

let main () =
  let a = Array.Parallel.init 4 (adder 10)
  let b = Array.Parallel.init 4 (scale 3)
  let add = adder 1
  let (x, y) = Parallel.both (fun () -> add 1) (fun () -> add 2)
  println $"{a.[0]} {a.[3]} {b.[1]} {b.[3]} {x} {y}"
