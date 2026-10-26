// [<NoAlloc>] (0012): a function that must not touch the heap, and the chain to where it does
let rec describe (n: int) : string = if n > 9 then describe (n / 10) else $"mode {n}"

let report (n: int) = String.length (describe n)

[<NoAlloc>]
let reply (n: int) : int = report n + 1

let main () = reply 2
