// Buffer.blit into a Buffer at an index near int's maximum, where j + n wraps below the length:
// the check is j <= length and n <= length - j, so it's out of range, not a write before the
// Buffer's storage
let main () =
  let src = [| 1; 2; 3; 4; 5; 6; 7; 8 |]
  let dst = Buffer.create 8 0
  Buffer.blit src 0 dst 0 8
  println $"{dst.[7]}"
  Buffer.blit src 0 dst 9223372036854775800 8
  println $"{dst.[0]}"
  0
