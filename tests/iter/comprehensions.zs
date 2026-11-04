// list and array expressions over any Iter (0017, step 5): a set, a map, a string, a Seq, a
// HashMap and a type of the program's own, through its impl, with the same forms as over a list
type Countdown = { from: int }

impl Iter<Countdown, int> =
  let forEach (c: Countdown) f =
    let mutable i = c.from
    let mutable go = true
    while go && i > 0 do
      go <- f i
      i <- i - 1
    go

let main () =
  let s = Set.ofList [ 3; 1; 2 ]
  let m = Map.ofList [ ("a", 1); ("b", 2); ("c", 3) ]
  let h = HashMap.ofList [ (1, "one") ]
  println $"{[ for x in s -> x * 10 ]} {[ for (k, v) in m do if v > 1 then yield k ]} {[| for c in "hi!" -> int c |] |> Array.toList}"
  println $"{[ for x in Seq.ofList [ 1; 2; 3 ] do if x <> 2 then yield x * x ]} {[ for (k, v) in h -> $"{k}={v}" ]} {[ for n in { from = 3 } -> n ]}"
  println $"{[ for x in s do for n in { from = x } -> (x, n) ] |> List.length} {Array.toList [| for x in Set.ofList [ "b"; "a" ] -> x |]}"
  0
