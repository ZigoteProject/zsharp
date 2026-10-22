// List and array expressions: a pure body is a pipeline fusion makes one loop of (it allocates
// only its result, or nothing under a consumer); any other runs in order
let main () =
  let xs = [ 1; 2; 3; 4; 5; 6 ]
  println $"{[ for x in xs -> x * x ]} {[ for i in 1 .. 5 -> i * i ]} {[ for i in 5 .. 1 -> i ]}"
  let before = Runtime.allocations ()
  let evens = [ for x in xs do if x % 2 = 0 then yield x * 10 ]
  let made = Runtime.allocations () - before
  let start = Runtime.allocations ()
  let total = List.sum [ for x in xs do if x > 2 then yield x * x ]
  let summed = Runtime.allocations () - start
  println $"{evens} allocations: {made}; sum {total} allocations: {summed}"
  let a = [| for i in 0 .. 4 -> i * 2 |]
  let b = [| for x in a -> x + 1 |]
  let c = [| for x in a do if x > 2 then yield x |]
  println $"{Array.toList a} {Array.toList b} {Array.toList c} {[ for x in a -> x / 2 ]}"
  // nested fors, let, match, yield!: in order
  let pairs = [ for x in 1 .. 3 do for y in 1 .. x -> (x, y) ]
  let opts = [ Some 1; None; Some 3 ]
  let somes = [ for o in opts do match o with | Some v -> yield v | None -> () ]
  let spliced = [ yield 0; yield! [ 1; 2 ]; yield! [| 3 |]; for (k, v) in [ (4, "a") ] -> k ]
  println $"{pairs} {somes} {spliced}"
  let logged =
    [ for i in 1 .. 3 do
      println $"at {i}"
      let twice = i * 2
      if twice > 2 then
        yield twice ]
  let names = [ for w in [ "ada"; "bo" ] do if String.length w > 2 then yield $"{w}!" ]
  println $"{logged} {names} {List.length xs}"
  0
