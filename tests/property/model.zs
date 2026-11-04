// properties (0010, steps 3 and 4): prop { } draws as it goes, assumes (a false assumption
// discards the case), classifies and labels; a passing property reports how its cases were
// labelled, a failure shows the failing case's labels. Prop.model checks a system against a
// model with a sequence of derived commands: a planted bug (a stack that loses its second
// element on a pop) is found and shrunk to the fewest commands
open Testing

[<Derive(Arbitrary)>]
type Command =
  | Push of int
  | Pop
  | Peek

// the system: a stack over an array, with the bug
type Stack = { items: list<int> }

let private apply (c: Command) (s: Stack) : Stack * option<int> =
  match (c, s.items) with
  | (Push n, items) -> ({ items = n :: items }, None)
  | (Pop, top :: _ :: rest) -> ({ items = rest }, Some top)
  | (Pop, top :: rest) -> ({ items = rest }, Some top)
  | (Pop, []) -> (s, None)
  | (Peek, top :: _) -> (s, Some top)
  | (Peek, []) -> (s, None)

let main () =
  Testing.runAll [
    testList "prop" [
      testProperty "division" (fun () ->
        prop {
          let! x = Gen.int ()
          let! y = Gen.int ()
          do! Prop.assume (y <> 0)
          do! Prop.classify (y < 10 && y > -10) "small divisor"
          return (x / y) * y + x % y = x
        })
    ]
  ] |> ignore
  // the model: a list; the system and the model must agree on every answer
  let step (c: Command) (pair: Stack * list<int>) : result<Stack * list<int>, string> =
    let (sys, model) = pair
    let (sys2, got) = apply c sys
    let (model2, want) =
      match (c, model) with
      | (Push n, xs) -> (n :: xs, None)
      | (Pop, x :: xs) -> (xs, Some x)
      | (Pop, []) -> ([], None)
      | (Peek, x :: _) -> (model, Some x)
      | (Peek, []) -> ([], None)
    if got = want then Ok(sys2, model2) else Error $"the stack gives {got}, the model {want}"
  let against : Model<Command, Stack, list<int>> =
    { init = (fun () -> ({ items = [] }, [])); step = step }
  Testing.runAll [
    testPropertyWith { seed = Some (u64 5) } "a stack agrees with a list" (fun (commands: list<Command>) ->
      Prop.model commands against)
  ]
