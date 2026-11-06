// Buffer.blit from an index near int's maximum, where i + n wraps below the source's length:
// out of range, not a read of the counted values before the source's storage (the destination
// has room for them, so only the source's test can catch it)
let main () =
  let words = Buffer.ofArray [| "a"; "b"; "c"; "d" |]
  let into = Buffer.create 8 ""
  Buffer.blit words 1 into 0 3
  println $"{into.[0]}{into.[2]}"
  Buffer.blit words 9223372036854775800 into 0 8
  println $"{into.[0]}"
  0
