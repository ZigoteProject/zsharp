// what a C union refuses: a read outside unsafe, a match, comparing, a case without one field
[<CLayout>]
type Data =
  | U32 of u32
  | F32 of f32

[<CLayout>]
type Two =
  | Pair of u32 * u32

[<CLayout>]
type Boxed =
  | Text of string

let read (d: Data) = d.U32

let which (d: Data) =
  match d with
  | U32 x -> x
  | F32 _ -> u32 0

let same (a: Data) (b: Data) = a = b

let shown (d: Data) = $"{d}"

let main () = 0
