/// `[<Bits>]` records (0013): a record that is one unsigned integer, its fields ranges of its bits
/// (a `bool` one bit, an enum the bits its cases need, `u8` to `u64` their size or `[<Width n>]`),
/// laid out from bit 0 or at `[<Bit n>]`. `[<Bits 32>]` fixes the width; without one it's the
/// smallest of 8, 16, 32 and 64 that holds the fields. Its equality, ordering and hashing are the
/// integer's. These convert between a record and its integer; its functions are built into the
/// compiler.
module Bits
