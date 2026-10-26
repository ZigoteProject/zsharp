// C unions (0004): no tag, each case a view of the same bytes
[<CLayout>]
type Data =
  | U32 of u32
  | U64 of u64
  | Ptr of cptr

[<CLayout>]
type Bits =
  | Float of f32
  | Word of u32
  | Bytes of fixed<u8, 4>

// a union in a struct, as C has them
[<CLayout>]
type Event = { kind: u8; data: Data }

assert sizeof<Data> = 8
assert alignof<Bits> = 4
assert offsetof<Event> "data" = 8

let main () =
  let d = U64(u64 4294967303)
  // the first four bytes, as C would read them
  println $"low {unsafe d.U32} all {unsafe d.U64}"
  let b = Float(f32 1.0)
  let bytes = unsafe b.Bytes
  println $"1.0f is {unsafe b.Word} ({bytes.[3]} {bytes.[2]} {bytes.[1]} {bytes.[0]})"
  // the bytes a case doesn't cover are zero
  let e = { kind = u8 1; data = U32(u32 9) }
  println $"event {e.kind} {unsafe e.data.U64} {sizeof<Event>}"
  // a case as a function
  let words = List.map Word [ u32 1065353216; u32 0 ]
  println $"floats {List.map (fun (w: Bits) -> unsafe w.Float) words}"
  0
