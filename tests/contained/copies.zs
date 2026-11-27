// a contained job's result is copied out of its memory (0035): every kind of Share value, the
// sharing between the job's objects kept, what the caller shared with the job not copied
open Threading

type Shape =
  | Dot
  | Circle of float
  | Poly of list<int * int>

type Row = { name: string; tags: array<string>; shape: Shape; next: option<string> }

let adder (n: int) : share<int -> int> = fun x -> x + n

let main () =
  // a record of a string, an array, a union and an option, in a list, in a tuple
  let rows =
    Contained.run (fun () ->
      let row (i: int) =
        { name = $"row {i}"
          tags = [| "a"; $"t{i}" |]
          shape = (if i = 0 then Dot else if i = 1 then Circle 1.5 else Poly [ (i, i); (0, 0) ])
          next = (if i = 2 then None else Some $"after {i}") }
      (List.init 3 row, "and a string", 7))
  match rows with
  | Ok(rs, s, n) ->
    for r in rs do
      println $"{r.name} {Array.toList r.tags} {r.shape} {r.next}"
    println $"{s} {n}"
  | Error p -> println $"failed: {p.message}"
  // a function made in the job, holding what the job made and what the caller shared
  let outside = [ 100; 200 ]
  let made =
    Contained.run (fun () ->
      let inside = List.map (fun x -> x + 1) outside
      let f : share<int -> int> = fun x -> x + List.sum inside + List.sum outside
      (f, adder 5))
  match made with
  | Ok(f, g) -> println $"{f 1} {g 1}"
  | Error p -> println $"failed: {p.message}"
  // a long list (copied in a loop, not by recursion) and a big array (not from the job's blocks)
  let big =
    Contained.run (fun () ->
      (List.init 1000000 (fun i -> i), Array.init 100000 (fun i -> $"{i % 10}")))
  match big with
  | Ok(xs, a) -> println $"{List.length xs} {List.sum xs} {Array.length a} {a.[99999]}"
  | Error p -> println $"failed: {p.message}"
  // sharing kept: one object the result refers to twice is copied once. The two jobs differ by
  // one array made in the job, and so by one in the copy
  let shared (n: int) =
    Contained.run (fun () ->
      let a = Array.create 8 n
      (a, a))
  let apart (n: int) =
    Contained.run (fun () ->
      let a = Array.create 8 n
      let b = Array.create 8 n
      (a, b))
  let count (job: int -> result<array<int> * array<int>, Panic>) : int =
    let before = Runtime.allocations ()
    job 3 |> ignore
    Runtime.allocations () - before
  println $"an array apart costs {count apart - count shared} allocations more: its own and its copy's"
  // what the caller shared isn't copied: the job gives back the caller's own object
  let table = List.init 1000 (fun i -> $"entry {i}")
  let before = Runtime.allocations ()
  let same = Contained.run (fun () -> table)
  let cost = Runtime.allocations () - before
  println $"giving back a list of 1000 strings cost {cost} allocations: {Result.map List.length same}"
  // a job's failure in the middle of building a big result
  println $"{Contained.run (fun () -> List.length (List.init 100000 (fun i -> if i = 99999 then panic "nearly" else $"{i}")))}"
