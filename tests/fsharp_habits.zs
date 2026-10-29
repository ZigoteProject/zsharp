// What an F# programmer writes in the first hour: let … in, a condition continued on a line
// starting with an operator, a record on the line after its constructor, a tuple scrutinee
// without parentheses, a module-level Buffer that's one Buffer, handle as a name, and
// [<CLayout>] on a private type
type Point = { x: int; y: int }

[<CLayout>]
type private Pair = { a: i32; b: i32 }

type private Log = { lines: Buffer<string> }

let private seen: Buffer<int> = Buffer.empty
let private log: Log = { lines = Buffer.empty }

effect Ask =
  abstract ask: unit -> int

let handle (x: int) = x + 1

let twice x = let y = x + 1 in y * 2

let either (a: bool) (b: bool) =
  if a
  || b then "yes" else "no"

let add (a: option<int>) (b: option<int>) =
  match a, b with
  | Some x, Some y -> x + y
  | Some x, None
  | None, Some x -> x
  | None, None -> 0

let asked () =
  handle Ask.ask () + Ask.ask () with
  | Ask.ask (), k -> k 20

let main () =
  let p =
    Some
      { x = 1; y = 2 }
  match p with
  | Some q -> println $"{q.x} {q.y}"
  | None -> ()
  let z = 3 in println $"{twice z} {z}"
  println $"{either false true} {either false false}"
  println $"{add (Some 1) (Some 2)} {add None (Some 4)} {add None None}"
  Buffer.push 7 seen
  Buffer.push 8 seen
  Buffer.push "one" log.lines
  println $"{Buffer.length seen} {Buffer.length log.lines}"
  println $"{handle 2} {asked ()}"
  let pair: Pair = { a = 5; b = 6 }
  println $"{pair.a + pair.b} {sizeof<Pair>}"
  0
