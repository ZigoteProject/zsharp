// Int's checked, saturating and bit operations (track S, item 3): on int, on the sized types,
// signed and unsigned; a count is an int whatever the width, and a rotation's amount is taken
// modulo the width, a negative one turning the other way
let main () =
  let big = 9223372036854775807
  let small = -9223372036854775807 - 1
  println $"{Int.checkedAdd big 1} {Int.checkedAdd 1 2} {Int.checkedSub small 1} {Int.checkedMul big 2} {Int.checkedMul (u8 15) (u8 17)} {Int.checkedMul (u8 16) (u8 16)} {Int.checkedSub (u32 0) (u32 1)}"
  println $"{Int.saturatingAdd big 1} {Int.saturatingSub (u8 3) (u8 5)} {Int.saturatingAdd (i8 100) (i8 100)} {Int.saturatingSub (i8 -100) (i8 100)} {Int.saturatingMul (i8 -100) (i8 2)} {Int.saturatingMul (i8 -100) (i8 -2)} {Int.saturatingMul (u16 300) (u16 300)} {Int.saturatingMul 3 4} {Int.saturatingMul small (-1)}"
  println $"{Int.popCount 255} {Int.popCount (u8 255)} {Int.popCount (-1)} {Int.popCount (i32 -1)} {Int.popCount 0}"
  println $"{Int.leadingZeros 1} {Int.leadingZeros (u8 1)} {Int.leadingZeros 0} {Int.leadingZeros (u16 0)} {Int.leadingZeros (-1)} {Int.trailingZeros 8} {Int.trailingZeros (u8 0)} {Int.trailingZeros 0}"
  println $"{Int.rotateLeft (u8 0b10010001) 1} {Int.rotateRight (u8 0b10010001) 1} {Int.rotateLeft (u32 0x80000001) 4} {Int.rotateLeft 1 64} {Int.rotateLeft 1 (-1)} {Int.rotateRight (u8 1) 9}"
  println $"{Int.byteSwap (u16 0x1234):X4} {Int.byteSwap (u32 0x12345678):X8} {Int.byteSwap (u8 0x12):X2} {Int.byteSwap (i16 1)} {Int.byteSwap 1}"
  // in a loop, as a checksum uses them
  let mutable h = u32 0xFFFFFFFF
  for b in [| u8 1; u8 2; u8 3 |] do
    h <- Int.rotateLeft (h ^^^ u32 b) 5
  println $"{h:X8} {Int.popCount h} {Int.trailingZeros h}"
  0
