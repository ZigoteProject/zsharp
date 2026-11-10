// [<NoAlloc>] and a value discarded: ignore drops it, which may free it (a string popped from an
// Spsc, which an interrupt handler would free under the program's allocator)
[<NoAlloc>]
let drain (q: Spsc<string>) = Spsc.pop q |> ignore

let main () =
  let q = Spsc.create 2
  Spsc.push q "a" |> ignore
  drain q
  0
