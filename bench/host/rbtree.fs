// A red-black tree (Okasaki's): inserting a million keys into a persistent tree, then looking
// each one up. The same algorithm as the Z# version, so .NET's GC meets Perceus.
type Color =
    | Red
    | Black

type Tree =
    | Empty
    | Node of Color * Tree * int * Tree

let balance c l k r =
    match c, l, k, r with
    | Black, Node(Red, Node(Red, a, x, b), y, c2), z, d
    | Black, Node(Red, a, x, Node(Red, b, y, c2)), z, d
    | Black, a, x, Node(Red, Node(Red, b, y, c2), z, d)
    | Black, a, x, Node(Red, b, y, Node(Red, c2, z, d)) -> Node(Red, Node(Black, a, x, b), y, Node(Black, c2, z, d))
    | _ -> Node(c, l, k, r)

let insert k t =
    let rec ins t =
        match t with
        | Empty -> Node(Red, Empty, k, Empty)
        | Node(c, l, x, r) -> if k < x then balance c (ins l) x r elif k > x then balance c l x (ins r) else t

    match ins t with
    | Node(_, l, x, r) -> Node(Black, l, x, r)
    | Empty -> Empty

let rec contains k t =
    match t with
    | Empty -> false
    | Node(_, l, x, r) -> if k < x then contains k l elif k > x then contains k r else true

[<EntryPoint>]
let main argv =
    let n = if argv.Length > 0 then int argv[0] else 1000000
    let mutable t = Empty
    let mutable seed = 42L

    for _ in 1..n do
        seed <- (seed * 1103515245L + 12345L) % 2147483648L
        t <- insert (int (seed % int64 n)) t

    let mutable found = 0

    for i in 0 .. n - 1 do
        if contains i t then
            found <- found + 1

    printfn "%d" found
    0
