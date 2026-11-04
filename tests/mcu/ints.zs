// Int's checked, saturating and bit operations on a chip (track S, item 3): the host's answers on
// i64 and u64 (two words there), u32, u16 and u8; the counts come back as the chip's 32-bit int
let main () =
  let big: i64 = 9223372036854775807
  let square: u64 = 4294967296
  let nibbles: u64 = 0xF0F0F0F0F0F0F0F0
  println $"{Int.checkedAdd big (i64 1)} {Int.checkedMul (u8 15) (u8 17)} {Int.checkedMul (u8 16) (u8 16)} {Int.checkedSub (u32 0) (u32 1)}"
  println $"{Int.saturatingAdd (i32 2147483647) (i32 1)} {Int.saturatingSub (u8 3) (u8 5)} {Int.saturatingMul (i8 -100) (i8 -2)} {Int.saturatingMul square square} {Int.saturatingAdd (-big) (i64 -2)}"
  println $"{Int.popCount nibbles} {Int.popCount (i32 -1)} {Int.leadingZeros (u64 1)} {Int.leadingZeros (u8 0)} {Int.trailingZeros square} {Int.trailingZeros (u16 0)}"
  println $"{Int.rotateLeft (u8 0b10010001) 1} {Int.rotateLeft (u32 0x80000001) 4} {Int.rotateRight (u64 1) 1} {Int.rotateLeft (u16 1) (-1)} {Int.byteSwap (u32 0x12345678):X8} {Int.byteSwap (u64 1)}"
  0
