// constants in flash on a chip (0014 item 1): the tables are static objects in the image, read
// with no startup code; a write copies one
let table = [| u32 0x00000000; u32 0x77073096; u32 0xEE0E612C; u32 0x990951BA |]
let words = [| "off"; "on"; "blink" |]
let gains = [| f32 0.5; f32 2.0 |]
let commands = [ "off"; "on"; "blink" ]
type Limits = { low: u16; high: u16; label: string }
type Tree =
  | Leaf
  | Node of Tree * int * Tree
let limits = { low = u16 10; high = u16 90; label = "temp" }
let tree = Node(Node(Leaf, 1, Leaf), 2, Node(Leaf, 3, Leaf))

let rec total (t: Tree) : int =
  match t with
  | Leaf -> 0
  | Node(l, v, r) -> total l + v + total r

let main () =
  let mutable sum = u32 0
  for i in 0 .. Array.length table - 1 do
    sum <- Int.wrappingAdd sum table.[i]
  println $"{sum:X8} {words.[2]} {gains.[1]}"
  let mutable copy = table
  copy.[1] <- u32 9
  println $"{table.[1]} {copy.[1]} {List.length commands} {List.head (List.rev commands)}"
  println $"{limits.label} {limits.high - limits.low} {total tree}"
  0
