// Compound assignment: += -= *= /= %= &&&= |||= ^^^= on anything <- assigns, the place
// evaluated once (its index and receiver bound first, then the read, the operation, the write)
type Pos = { x: int; y: int }
type Player = { name: string; pos: Pos; score: int }

let main () =
  let mutable total = 0

  for i in 1 .. 10 do
    total += i * i

  let r = ref 1
  r.Value *= 6
  r.Value -= 2
  let mutable bits = 0b1100
  bits &&&= 0b0110
  bits |||= 0b0001
  bits ^^^= 0b1111
  let mutable s = "a"
  s += "b"
  println $"{total} {r.Value} {bits} {s}"

  // an element: the index is computed once, even when it has an effect
  let mutable a = [| 10; 20; 30 |]
  let calls = ref 0

  let next () =
    calls.Value += 1
    calls.Value

  a.[next ()] += 5
  a.[0] /= 2
  a.[2] %= 7
  println $"{Array.toList a} calls: {calls.Value}"

  // a field of a let mutable record, nested too
  let mutable p = { name = "ada"; pos = { x = 1; y = 2 }; score = 0 }
  p.score += 10
  p.pos.x += 5
  p.pos <- { x = p.pos.x * 2; y = 0 }
  println $"{p.name} {p.pos.x} {p.pos.y} {p.score}"

  // a Buffer's element, the Buffer from a call made once
  let buf = Buffer.create 3 1
  let made = ref 0

  let theBuffer () =
    made.Value += 1
    buf

  (theBuffer ()).[1] += 41
  println $"{buf.[1]} made: {made.Value}"
  0
