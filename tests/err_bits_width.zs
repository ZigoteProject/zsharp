// Bits.toU16 on a 32-bit record (0013)
[<Bits 32>]
type Reg = { on: bool = false }

let main () = int (Bits.toU16 { on = true })
