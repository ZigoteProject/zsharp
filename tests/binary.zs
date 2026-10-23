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
  0
