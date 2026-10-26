// Layout facts (0004): sizeof<T>, alignof<T> and offsetof<T> "field" are int constants, a
// [<CLayout>] type's as C lays it out; a top-level assert on constants is checked when compiling.
[<CLayout>]
type Packet = { kind: u8; length: u32; data: fixed<u8, 6>; flags: u16 }

type Pair<'a> = { first: u8; second: 'a }

type Shape =
  | Circle of f64
  | Rect of f64 * f64

let headerSize = sizeof<Packet>

assert (sizeof<Packet> = 16)
assert (offsetof<Packet> "length" = 4 && alignof<Packet> = 4)
assert (sizeof<int> = 8 || sizeof<int> = 4)

// in a generic function, known once the function is monomorphized
let sizeOfPair (x: 'a) = sizeof<Pair<'a>>

let offsetOfSecond (x: 'a) = offsetof<Pair<'a>> "second"

let main () =
  println $"{headerSize} {sizeof<u8>} {sizeof<f64>} {sizeof<string>} {sizeof<list<int>>} {sizeof<option<int>>} {sizeof<Shape>} {sizeof<int * u8>} {sizeof<span<u8>>}"
  println $"{offsetof<Packet> "data"} {offsetof<Packet> "flags"} {alignof<Packet>} {alignof<f64>}"
  println $"{sizeOfPair (u8 1)} {sizeOfPair 1.0} {offsetOfSecond (u16 2)} {offsetOfSecond 2.0}"
  0
