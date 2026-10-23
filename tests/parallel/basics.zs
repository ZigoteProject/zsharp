// The thread pool: both, for, reduce, Array.Parallel, and the values threads share.

let rec fib (n: int) : int = if n < 2 then n else fib (n - 1) + fib (n - 2)

type Shape =
  | Circle of float
  | Square of float

let area (s: Shape) =
  match s with
  | Circle r -> 3.0 * r * r
  | Square a -> a * a

// a top-level value: shared, so every thread may read it
let primes = [ 2; 3; 5; 7; 11 ]

type Node =
  | Leaf
  | Node of Node * int * Node

let rec insert (x: int) (t: Node) : Node =
  match t with
  | Leaf -> Node (Leaf, x, Leaf)
  | Node (l, v, r) -> if x < v then Node (insert x l, v, r) else Node (l, v, insert x r)

let rec size (t: Node) : int =
  match t with
  | Leaf -> 0
  | Node (l, _, r) -> size l + 1 + size r

let main () =
  // two results at once
  let (a, b) = Parallel.both (fun () -> fib 25) (fun () -> fib 26)
  println $"both: {a} {b}"

  // a captured list and string cross threads (marked shared): both sides read them
  let names = [ "ada"; "grace"; "edsger" ]
  let greeting = "hello"
  let (n1, n2) =
    Parallel.both (fun () -> List.length names) (fun () ->
      String.length greeting + List.length names)
  println $"captured: {n1} {n2}"

  // for, counting with an Atomic
  let hits = Atomic.make 0
  Parallel.for 0 1000 (fun i -> if i % 3 = 0 then Atomic.add hits 1 |> ignore)
  println $"for: {Atomic.get hits}"

  // reduce
  let total = Parallel.reduce 0 10001 0 (fun i -> i) (fun x y -> x + y)
  println $"reduce: {total}"
  let none = Parallel.reduce 5 5 -1 (fun i -> i) (fun x y -> x + y)
  println $"reduce of nothing: {none}"

  // arrays built in parallel, of plain values and of objects
  let squares = Array.Parallel.init 20 (fun i -> i * i)
  println $"init: {squares.[0]} {squares.[7]} {squares.[19]} ({Array.length squares})"
  let shapes = Array.init 100 (fun i -> if i % 2 = 0 then Circle (float i) else Square (float i))
  let areas = Array.Parallel.map area shapes
  println $"map: {areas.[2]} {areas.[3]} {Array.sum areas}"
  let words = Array.Parallel.init 5 (fun i -> $"w{i * i}")
  println $"strings: {words.[3]} {Array.length words}"

  // a Mutex: updates from every thread, none lost
  let log = Mutex.make []
  Parallel.for 0 100 (fun i -> Mutex.update log (fun xs -> i :: xs) |> ignore)
  println $"mutex: {List.length (Mutex.get log)} {List.sum (Mutex.get log)}"

  // compareExchange and exchange
  let flag = Atomic.make false
  let first = Atomic.compareExchange flag false true
  let second = Atomic.compareExchange flag false true
  println $"cas: {first} {second} {Atomic.exchange flag false} {Atomic.get flag}"
  let x = Atomic.make 1.5
  println $"float: {Atomic.add x 2.0}"

  // a Channel between the pool's jobs: one sends, the other receives
  let ch = Channel.make 64 // room for all of them: with one worker, the receiver runs after the sender
  let sender () =
    for i in 1 .. 50 do
      Channel.send ch $"m{i}"
    Channel.close ch
    50
  let receiver () =
    let mutable count = 0
    let mutable going = true
    while going do
      match Channel.receive ch with
      | Some _ -> count <- count + 1
      | None -> going <- false
    count
  let (sent, got) = Parallel.both sender receiver
  println $"channel: {sent} {got}"
  println $"workers: {Parallel.workers () > 0}"

  // a top-level list read on every thread
  let found =
    Parallel.reduce 0 100 0 (fun i -> if List.contains i primes then 1 else 0) (fun x y -> x + y)
  println $"primes below 100 in the list: {found}"

  // a shared array changed in a job: copied there, so the original is unchanged
  let base = Array.init 10 (fun i -> i)
  let changed = Array.Parallel.init 4 (fun k ->
    let mutable mine = base
    mine.[0] <- 100 + k
    mine.[0] + mine.[9])
  println $"copy on write: {changed.[0]} {changed.[3]} {base.[0]}"

  // a shared tree, and trees built on each thread (in arenas, too) that come back
  let tree = List.fold (fun t x -> insert x t) Leaf [ 50; 20; 80; 10; 30; 70; 90 ]
  let sizes = Array.Parallel.init 8 (fun k -> size (insert (k * 7) tree))
  println $"trees: {Array.sum sizes}"
  let built =
    Array.Parallel.init 4 (fun k ->
      Arena.with (fun () ->
        size (List.fold (fun t x -> insert x t) Leaf (List.init 100 (fun i -> (i * 37 + k) % 101)))))
  println $"arenas: {Array.sum built}"
  let back =
    Array.Parallel.init 3 (fun k -> List.fold (fun t x -> insert x t) Leaf [ k; k + 1; k + 2 ])
  println $"returned: {size back.[0] + size back.[1] + size back.[2]}"
