// A record literal takes its record from the type expected where it is written, when several
// records have the same fields: the later declared one wins only without such a type.
type Meters = { a: float; b: float }
type Pair = { a: float; b: float }

let lengthOf (m: Meters) = m.a + m.b

let both (p: Meters * Pair) = (fst p).a + (snd p).b

let main () =
  println $"argument {lengthOf { a = 1.0; b = 2.0 }}"
  println $"tuple {both ({ a = 1.0; b = 0.0 }, { a = 0.0; b = 5.0 })}"
  let m: Meters = { a = 3.0; b = 4.0 }
  println $"annotated {lengthOf m}"
  let flip = true
  let fromIf: Meters = if flip then { a = 1.0; b = 1.0 } else { a = 2.0; b = 2.0 }
  println $"if {lengthOf fromIf} {lengthOf (if flip then { a = 0.5; b = 0.5 } else { a = 0.0; b = 0.0 })}"
  let fromMatch: Meters =
    match 3 with
    | 1 -> { a = 1.0; b = 0.0 }
    | n ->
      let half = float n / 2.0
      { a = half; b = half }
  println $"match {lengthOf fromMatch}"
  let ms: list<Meters> = [ { a = 1.0; b = 1.0 }; { a = 2.0; b = 2.0 } ]
  println $"list {List.sumBy lengthOf ms}"
  let arr: array<Meters> = [| { a = 5.0; b = 5.0 } |]
  println $"array {lengthOf arr.[0]}"
  let p = { a = 7.0; b = 8.0 }
  println $"no expected type: Pair {p.a + p.b}"
  0
