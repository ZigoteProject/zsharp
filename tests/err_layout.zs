// a top-level assert on constants fails the build, naming the facts it read
[<CLayout>]
type Packet = { kind: u8; length: u32 }

assert (sizeof<Packet> = 20)
assert (offsetof<Packet> "lenght" = 4)
assert (offsetof<int> "x" = 0)

let main () = 0
