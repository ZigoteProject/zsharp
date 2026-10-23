// Effects in the corners: members, record fields typed with effects, partial application, a
// trait constraint beside an effect, handlers inside recursion (phase 10)

effect Log =
  abstract log : string -> unit

type Counter =
  { name: string }
  member c.Tick (n: int) = Log.log $"{c.name} {n}"

// a field whose function performs Log, written in the type
type Step = { run: int -> int / Log }

let double x =
  Log.log $"doubling {x}"
  x * 2

let steps = [ { run = fun x -> x + 1 }; { run = double } ]

let prefixed (p: string) (s: string) = Log.log (p + s)

// Show and an effect together
let logAll (xs: list<'a>) = List.iter (fun x -> Log.log (string x)) xs

// a handler at every level of a recursion: each level's logs, indented
let rec nest n =
  if n > 0 then
    let inner =
      handle nest (n - 1) with
      | Log.log s, k ->
        Log.log ("  " + s)
        k ()
    Log.log $"level {n}"
    inner + 1
  else 0

let collect f =
  let mutable lines = []
  handle f () with
  | Log.log s, k ->
    lines <- s :: lines
    k ()
  List.rev lines

let main () =
  let counter: Counter = { name = "c" }
  println $"{collect (fun () -> counter.Tick 3)}"
  println $"{collect (fun () -> println (string (List.fold (fun acc s -> s.run acc) 5 steps)))}"
  println $"{collect (fun () -> List.iter (prefixed "> ") [ "a"; "b" ])}"
  println $"{collect (fun () -> logAll [ 1; 2 ])}"
  println $"{collect (fun () -> println (string (nest 3)))}"
  0
