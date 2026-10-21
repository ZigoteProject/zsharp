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
  let p = { a = 7.0; b = 8.0 }
  println $"no expected type: Pair {p.a + p.b}"
  0
