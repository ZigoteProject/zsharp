// Layout facts on a 32-bit chip (0004): int, usize and heap values are the 32-bit word, and an
// i64 is aligned to 8 bytes, as C lays them out for the target
[<CLayout>]
type Packet = { kind: u8; length: u32; data: fixed<u8, 6>; flags: u16 }

type Pair<'a> = { first: u8; second: 'a }

assert (sizeof<int> = 4 && sizeof<string> = 4 && sizeof<span<u8>> = 12)
assert (sizeof<Packet> = 16 && alignof<i64> = 8)

let sizeOfPair (x: 'a) = sizeof<Pair<'a>>

let main () =
  println $"{sizeof<int>} {sizeof<option<int>>} {sizeof<int * u8>} {sizeof<Packet>} {sizeOfPair (i64 1)} {sizeOfPair 1}"
  0
