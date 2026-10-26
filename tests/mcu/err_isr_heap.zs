// an interrupt handler is [<NoAlloc>] (0012): the allocator isn't reentrant
let log: Spsc<string> = Spsc.create 4

[<Interrupt 3>]
let onLine3 () = Spsc.push log $"line {3}" |> ignore

let main () = 0
