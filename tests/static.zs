// constants in flash (0014 items 1 and 3): a top-level array or list literal of numbers, bools or
// strings is a static object in the image, not built at startup: reading it allocates nothing, a
// write copies it (a static is never unique), and the strings in it are statics too; a record,
// tuple or union of constants is written into its global, its tables, lists and boxed cases
// static objects
type Point = { x: int; y: int; name: string }
type Shape =
  | Circle of f64
  | Rect of int * int
type Tree =
  | Leaf
  | Node of Tree * int * Tree
type Color =
  | Red
  | Green
  | Blue
type Id = Id of u16
let crc = [| u32 0x00000000; u32 0x77073096; u32 0xEE0E612C; u32 0x990951BA |]
let names = [| "zero"; "one"; "two" |]
let flags = [| true; false; true |]
let weights = [| 0.5; 1.25; -2.0 |]
let small = [| i8 -3; i8 7 |]
let primes = [ 2; 3; 5; 7 ]
let commands = [ "off"; "on"; "blink" ]
let origin = { x = 1; y = 2; name = "origin" }
let triple = (3, "three", 4.5)
let shape = Rect(2, 3)
let tree = Node(Node(Leaf, 1, Leaf), 2, Node(Leaf, 3, Leaf))
let color = Green
let some = Some "yes"
let none : option<string> = None
let ident = Id(u16 7)
let points = [| { x = 1; y = 1; name = "a" }; { x = 2; y = 2; name = "b" } |]
let shapes = [ Circle 1.5; Rect(4, 5) ]
let big: i64 = 9223372036854775807

let rec total (t: Tree) : int =
  match t with
  | Leaf -> 0
  | Node(l, v, r) -> total l + v + total r

let main () =
  let mutable sum = u32 0
  for i in 0 .. Array.length crc - 1 do
    sum <- Int.wrappingAdd sum crc.[i]
  println $"{sum:X8} {names.[1]} {flags.[2]} {weights.[1]} {small.[0] + small.[1]}"
  let mutable copy = crc
  copy.[0] <- u32 1
  println $"{crc.[0]} {copy.[0]} {Array.toList names} {Array.length flags}"
  // static lists: cells in the image, the last pointing at the static []; a longer list shares
  // them, and taking the tail is reading
  let more = 1 :: primes
  match commands with
  | first :: rest ->
    println $"{List.sum primes} {List.length more} {first} {rest} {List.tail more = primes}"
  | [] -> ()
  let (a, b, c) = triple
  println $"{origin.name} {origin.x + origin.y} {a} {b} {c} {shape} {total tree} {color} {some} {none} {ident} {points.[1].name} {List.length shapes} {big}"
  let moved = { origin with x = 10 }
  let area =
    match shapes with
    | Circle r :: _ -> int (r * r)
    | Rect(w, h) :: _ -> w * h
    | [] -> 0
  println $"{moved.x} {origin.x} {area}"
  0
