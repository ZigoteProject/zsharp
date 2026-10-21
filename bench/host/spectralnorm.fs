// Spectral norm (the Benchmarks Game): floating-point loops over arrays.
let a i j = 1.0 / float ((i + j) * (i + j + 1) / 2 + i + 1)

let multiplyAv n (v: float[]) =
    Array.init n (fun i ->
        let mutable s = 0.0

        for j in 0 .. n - 1 do
            s <- s + a i j * v[j]

        s)

let multiplyAtv n (v: float[]) =
    Array.init n (fun i ->
        let mutable s = 0.0

        for j in 0 .. n - 1 do
            s <- s + a j i * v[j]

        s)

let multiplyAtAv n v = multiplyAtv n (multiplyAv n v)

[<EntryPoint>]
let main argv =
    let n = if argv.Length > 0 then int argv[0] else 1000
    let mutable u = Array.create n 1.0
    let mutable v = Array.create n 0.0

    for _ in 1..10 do
        v <- multiplyAtAv n u
        u <- multiplyAtAv n v

    let mutable vBv = 0.0
    let mutable vv = 0.0

    for i in 0 .. n - 1 do
        vBv <- vBv + u[i] * v[i]
        vv <- vv + v[i] * v[i]

    printfn "%d" (int64 (sqrt (vBv / vv) * 1000000000.0))
    0
