// Binary trees (the Benchmarks Game): allocating and walking many small trees, with .NET's GC.
type Tree =
    | Leaf
    | Node of Tree * Tree

let rec make depth =
    if depth = 0 then Node(Leaf, Leaf) else Node(make (depth - 1), make (depth - 1))

let rec check t =
    match t with
    | Leaf -> 0
    | Node(l, r) -> 1 + check l + check r

[<EntryPoint>]
let main argv =
    let n = if argv.Length > 0 then int argv[0] else 16
    let maxDepth = max 6 n
    let stretch = maxDepth + 1
    printfn "stretch tree of depth %d\t check: %d" stretch (check (make stretch))
    let longLived = make maxDepth
    let mutable d = 4

    while d <= maxDepth do
        let iterations = 1 <<< (maxDepth - d + 4)
        let mutable total = 0

        for _ in 1..iterations do
            total <- total + check (make d)

        printfn "%d\t trees of depth %d\t check: %d" iterations d total
        d <- d + 2

    printfn "long lived tree of depth %d\t check: %d" maxDepth (check longLived)
    0
