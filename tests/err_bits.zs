// what a [<Bits>] record can't be (0013)
[<Bits 8>]
type Wide = { a: u8; b: bool }

[<Bits>]
type Overlap = { [<Width 4>] a: u8; [<Bit 2>] b: bool }

[<Bits>]
type Signed = { a: int }

[<Bits>]
type OneBit = { [<Width 2>] on: bool }

type Plain = { [<Width 4>] a: u8 }

[<Bits 12>]
type Odd = { a: bool }

let main () = 0
