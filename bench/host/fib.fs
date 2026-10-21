// Recursive Fibonacci: calls and integer arithmetic (64-bit, wrapping on overflow).
let rec fib (n: int64) = if n < 2L then n else fib (n - 1L) + fib (n - 2L)

[<EntryPoint>]
let main argv =
    let n = if argv.Length > 0 then int64 argv[0] else 32L
    printfn "%d" (fib n)
    0
