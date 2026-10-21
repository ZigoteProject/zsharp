// A lambda without parameter types is typed after the call's other arguments, and gets the
// parameter types expected of it: members resolve inside it without annotations, with |> or
// without (F# needs the |>).
type Point = { x: int; y: int }

// the same fields as Point, declared later: a record literal alone would mean Vec
type Vec = { x: int; y: int }

let norm (p: Point) = p.x * p.x + p.y * p.y

let applyTo (f: string -> int) = f "four"

// f's type is unknown until x reaches it
let twice f x = x |> f |> f

let main () =
  let names = [ "ab"; "cde" ]
  let lengths = names |> List.map (fun s -> s.Length)
  println $"{List.sum lengths} {List.sum (List.map (fun s -> s.Length) names)}"
  println $"{List.fold (fun total s -> total + s.Length) 0 names}"
  let long = [ "x"; "yz" ] |> List.filter (fun s -> s.Length > 1) |> List.length
  println $"{long}"
  let upper = [| "a"; "bb" |] |> Array.map (fun s -> s.ToUpper())
  println upper.[1]
  let n = "abc" |> fun s -> s.Length
  let m = ("ab", 2) |> fun (s, k) -> s.Length * k
  println $"{n} {m}"
  println $"{applyTo (fun s -> s.Length)}"
  println $"{twice (fun k -> k * 2) 3}"
  // an annotated lambda keeps its place, so it still tells the list what records it holds
  let sizes = List.map (fun (p: Point) -> norm p) [ { x = 1; y = 2 }; { x = 3; y = 4 } ]
  let one = { x = 1; y = 2 } |> norm
  println $"{List.sum sizes} {one}"
  0
