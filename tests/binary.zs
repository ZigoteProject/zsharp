// Binary (0020): values to bytes and back: derived records and unions, the library's types,
// strings written once, and errors for bytes that hold no value.
[<Derive(Binary)>]
type Point = { x: int; y: f64; name: string }

[<Derive(Binary)>]
type Shape =
  | Circle of Point * f64
  | Poly of list<Point>
  | Empty

[<Derive(Binary)>]
type Tree =
  | Leaf
  | Node of Tree * int * Tree

// types that hold each other derive together
[<Derive(Binary)>]
type Expr =
  | Num of int
  | Block of list<Stmt>

and Stmt = { label: string; body: Expr }

let same (x: 'a) : bool =
  match Binary.ofBytes (Binary.toBytes x) with
  | Ok y -> y = x
  | Error _ -> false

let main () =
  let p = { x = -5; y = 2.5; name = "origin" }
  println $"{same p} {same (Poly [ p; p ])} {same Empty} {same (Circle (p, 1.0))}"
  let t = Node (Node (Leaf, 1, Leaf), 2, Node (Leaf, -3, Leaf))
  println $"{same t} {same (Map.ofList [ (1, "a"); (2, "b") ])} {same (Set.ofList [ 'x'; 'y' ])}"
  println $"{same (Some (Ok 4 : result<int, string>))} {same (1, "two", 3.0)} {same [ u64 0xFFFF_FFFF_FFFF_FFFF; u64 0 ]}"
  println $"{same (i8 -128, u16 65535)} {same "héllo"} {same ()} {same [ true; false ]}"
  let a: result<array<int>, string> = Binary.ofBytes (Binary.toBytes [| 1; -2; 300 |])
  println $"{Result.map (fun (x: array<int>) -> Array.toList x) a}"
  // a string written again is a number: 1 (the count) + 5 (the first) + 1 + 1
  println $"{Array.length (Binary.toBytes [ "abc"; "abc"; "abc" ])}"
  let short: result<int, string> = Binary.ofBytes [| u8 200 |]
  let long: result<int, string> = Binary.ofBytes [| u8 0; u8 0 |]
  let wrong: result<Shape, string> = Binary.ofBytes (Binary.toBytes "Square")
  println $"{short} {long} {wrong}"
  let program =
    Block [ { label = "a"; body = Num 1 }
      { label = "b"; body = Block [ { label = "c"; body = Num -2 } ] } ]
  println $"{same program} {same { label = "top"; body = program }}"
  // lengths from elsewhere: a string's of 2^64 - 1 or 2^63 (a negative int, converted first), a
  // string's number past int's, a list's negative or past the bytes left (or of units, past the
  // cap): each an Error, nothing read or made of the size it claims
  let huge =
    [| u8 0; u8 255; u8 255; u8 255; u8 255; u8 255; u8 255; u8 255; u8 255; u8 255; u8 1 |]
  let half =
    [| u8 0; u8 128; u8 128; u8 128; u8 128; u8 128; u8 128; u8 128; u8 128; u8 128; u8 1 |]
  let s1: result<string, string> = Binary.ofBytes huge
  let s2: result<Shape, string> = Binary.ofBytes half
  let s3: result<string, string> = Binary.ofBytes huge.[1..]
  println $"{s1} {s2} {s3}"
  let l1: result<list<unit>, string> = Binary.ofBytes [| u8 1 |]
  let l2: result<list<unit>, string> = Binary.ofBytes half.[1..]
  let l3: result<array<int>, string> = Binary.ofBytes [| u8 0xD0; u8 0x0F; u8 2 |]
  println $"{l1} {l2} {Result.map (fun (x: array<int>) -> Array.toList x) l3} {same [ (); (); () ]}"
  // nesting: past the limit an Error, not a stack run out (after "Node" once, a level is a byte)
  let deep = Buffer.ofArray [| u8 0; u8 4; u8 78; u8 111; u8 100; u8 101 |]
  for _ in 1 .. 2000 do
    Buffer.push (u8 1) deep
  let d1: result<Tree, string> = Binary.ofBytes deep
  let d2: result<Tree, string> = Binary.ofBytesWith { depth = 3000 } deep
  let rec chain (n: int) (t: Tree) = if n = 0 then t else chain (n - 1) (Node (t, n, Leaf))
  let long = chain 1500 Leaf
  let cut: result<Tree, string> = Binary.ofBytes (Binary.toBytes long)
  let whole: result<Tree, string> = Binary.ofBytesWith { depth = 2000 } (Binary.toBytes long)
  println $"{d1} {d2} {cut} {whole = Ok long}"
  // numbers: i64 and int as the same bytes, i64's ends; one too big for its type an Error
  let narrow: result<i8, string> = Binary.ofBytes (Binary.toBytes 300)
  let small: result<u16, string> = Binary.ofBytes (Binary.toBytes (u64 70000))
  let sameBytes = Array.toList (Binary.toBytes (i64 -5)) = Array.toList (Binary.toBytes -5)
  println $"{sameBytes} {same (i64 -9223372036854775807 - i64 1, i64 9223372036854775807)} {narrow} {small}"
  // a literal only Binary constrains is an int (a float an f64), not the first type with an impl
  // (i16, which held 70000 as 4464, and f32)
  let lits: result<list<int>, string> = Binary.ofBytes (Binary.toBytes [ 70000; 1073741824 ])
  let tenth: result<f64, string> = Binary.ofBytes (Binary.toBytes 0.1)
  println $"{lits} {tenth} {Array.length (Binary.toBytes 70000)}"
  0
