// [<NoAlloc>] and a Buffer popped from a Buffer of them and discarded: the message names its type
// as a Buffer's cell, not as a row type's ColumnBuffer (0037 named every Buffer so)
[<NoAlloc>]
let drain (q: Buffer<Buffer<int>>) = Buffer.pop q |> ignore

let main () =
  drain (Buffer.ofArray [| Buffer.ofArray [| 1 |] |])
  0
