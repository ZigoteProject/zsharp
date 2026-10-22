let first (a: array<u8>) = a.[0]

let main () =
  let bytes = String.bytes "ab"
  println $"{first bytes}"
  0
