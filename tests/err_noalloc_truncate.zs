// [<NoAlloc>] and a Buffer shortened: the elements past its new end are dropped, which may free
// them
[<NoAlloc>]
let cut (b: Buffer<string>) = Buffer.truncate 1 b

let main () =
  let b = Buffer.ofArray [| "a"; "b" |]
  cut b
  println $"{Buffer.length b}"
  0
