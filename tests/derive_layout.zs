// A derive reads its type's layout: sizeof<'self>, alignof<'self> and a record field's f.offset
// (offsetof<'self> of it), a generic record's at each of its types. A layout attribute goes
// beside a derive in one list.
trait Layout<'a> =
  abstract layout : 'a -> string

let private sizeOf (x: 'a) = sizeof<'a>

derive Layout =
  let layout (x: 'self) =
    match Shape.of x with
    | Record r ->
      let mutable s = $"{sizeof<'self>}/{alignof<'self>}:"
      for f in r.fields do
        s <- s + $" {f.name}@{f.offset}+{sizeOf f.value}"
      s
    | Union c -> $"{sizeof<'self>}/{alignof<'self>}: {c.name}"

trait Names<'a> =
  abstract names : 'a -> string

derive Names =
  let names (x: 'self) =
    match Shape.of x with
    | Record r ->
      let mutable s = $"{sizeof<'self>}:"
      for f in r.fields do
        s <- s + $" {f.name}={f.value}"
      s
    | Union c -> c.name

[<Derive(Layout)>]
type Loose = { a: u8; b: i64; c: u8; d: i32 }

[<Derive(Layout)>]
type Pair<'a> = { first: u8; second: 'a }

[<CLayout; Derive(Layout)>]
type Packet = { kind: u8; length: u32; data: fixed<u8, 6>; flags: u16 }

[<Derive(Layout)>]
type Figure =
  | Dot
  | Circle of f64
  | Rect of f64 * f64

[<Derive(Layout)>]
type Level =
  | Low
  | High

[<Bits 32; Derive(Names)>]
type Control = { on: bool = false; mode: u8 = u8 0; ready: bool = false }

let main () =
  println (layout { a = u8 1; b = i64 2; c = u8 3; d = i32 4 })
  println (layout { first = u8 1; second = u16 2 })
  println (layout { first = u8 1; second = 2.0 })
  println (layout ({ kind = u8 1; length = u32 2; data = Fixed.create (u8 0); flags = u16 3 } : Packet))
  println (layout (Rect (1.0, 2.0)))
  println (layout Dot)
  println (layout High)
  println (names { on = true; mode = u8 3; ready = false })
  println $"{offsetof<Packet> "flags"} {sizeof<Control>}"
  0
