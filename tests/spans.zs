// Spans and slices: windows without copies. An array or a Buffer is a span where one is
// expected; a Buffer's slice is a Buffer sharing its storage; a string's slice is a string.
let header (bytes: span<u8>) = Array.sum bytes.[..3]

// a parser over bytes, from a span and an index: the numbers in a line of digits and spaces
let rec numbers (s: span<u8>) (i: int) (acc: list<int>) =
  if i >= Span.length s then
    List.rev acc
  else if s.[i] = u8 32 then
    numbers s (i + 1) acc
  else
    let mutable j = i
    let mutable n = 0
    while j < Span.length s && s.[j] <> u8 32 do
      n <- n * 10 + int (s.[j] - u8 48)
      j <- j + 1
    numbers s j (n :: acc)

let main () =
  let a = [| 1; 2; 3; 4; 5; 6 |]
  let mid = a.[1..3]
  println $"{Array.sum a} {Array.sum mid} {Array.sum a.[..1]} {Array.sum a.[4..]} {Span.length mid.[1..]} {mid.[0]} {mid.Length}"
  let b = Buffer.ofArray a
  let w = b.[2..4]
  w.[0] <- 30
  b.[4] <- 50
  w.[1] += 100
  println $"{Array.sum b} {Array.sum w} {Array.sum b.[..1]} {Array.toList (Buffer.toArray w)} {b.[2]} {b.[3]} {Buffer.length (Buffer.slice b 1 2)}"
  // a span keeps its array alive after the array's last other reference goes
  let kept = (Array.init 5 (fun i -> i * i)).[2..]
  println $"{Array.toList (Array.ofSpan kept)} {Span.isEmpty kept.[3..]} {Array.toList (Array.map (fun x -> x + 1) kept)}"
  // a file's bytes read once, parsed through spans without a copy
  let path = "/tmp/zs-spans-test.txt"
  File.writeAllText path "12 345 6" |> ignore
  match File.readAllText path with
  | Ok text ->
    let bytes = String.bytes text
    let before = Runtime.allocations ()
    let ns = numbers bytes 0 []
    let made = Runtime.allocations () - before
    println $"{ns} {made} allocations (the list's cells); header {header bytes}"
  | Error e -> println e
  // SIMD loads read spans too
  let fs = [| f32 1.0; f32 2.0; f32 3.0; f32 4.0; f32 5.0 |]
  println $"{F32x4.sum (F32x4.load fs.[1..] 0)} {F32x4.sum (F32x4.load fs 1)}"
  let s = "héllo"
  println $"{s.[0..2]} {s.[3..]} {String.ofBytes (String.bytes s).[1..2]} {String.ofBytes (String.bytes s).[..1]}! {String.length s.[..0]}"
  0
