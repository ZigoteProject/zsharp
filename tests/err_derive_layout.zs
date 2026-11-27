// what a derive can't ask of a layout: a union case's field has no offset in the type, a
// [<Bits>] record's fields are bits and not bytes, and a type has one layout attribute
trait Offsets<'a> =
  abstract offsets : 'a -> int

derive Offsets =
  let offsets (x: 'self) =
    match Shape.of x with
    | Record r ->
      let mutable n = 0
      for f in r.fields do
        n <- n + f.offset
      n
    | Union c ->
      let mutable n = 0
      for f in c.fields do
        n <- n + f.offset
      n

[<Derive(Offsets)>]
type Figure =
  | Circle of f64

[<Bits 8; Derive(Offsets)>]
type Control = { on: bool = false }

[<CLayout; Bits 8>]
type Both = { ready: bool = false }

assert (offsetof<Control> "on" = 0)

let main () = 0
