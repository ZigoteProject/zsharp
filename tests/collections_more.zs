// The rest of F#'s List, Array, Map and Set functions, and Queue, Stack and PriorityQueue (S2)
let show (xs: array<'a>) = Array.toList xs

let main () =
  let words = [ "apple"; "bob"; "avocado"; "cat"; "banana"; "axe" ]
  println $"{List.groupBy (fun (w: string) -> String.sub w 0 1) words}"
  println $"{List.countBy String.length words}"
  println $"{List.chunkBySize 4 (List.init 10 (fun i -> i + 1))} {List.windowed 3 [ 1; 2; 3; 4; 5 ]} {List.windowed 9 [ 1; 2 ]}"
  println $"{List.pairwise [ 1; 2; 3; 4 ]} {List.pairwise [ 1 ]}"
  println $"{List.scan (+) 0 [ 1; 2; 3 ]} {List.foldBack (fun x acc -> x :: acc) [ 1; 2; 3 ] [ 9 ]}"
  let a = [| 5; 1; 4; 2; 3 |]
  println $"{show (Array.map (fun (k, g) -> (k, show g)) (Array.groupBy (fun x -> x % 2) a))} {show (Array.countBy (fun x -> x > 2) a)}"
  println $"{show (Array.map show (Array.chunkBySize 2 a))} {show (Array.map show (Array.windowed 4 a))} {show (Array.pairwise a)}"
  println $"{show (Array.scan (+) 0 a)} {Array.foldBack (fun x acc -> acc * 10 + x) a 0} {Array.tryFindIndex (fun x -> x = 4) a} {Array.tryFindIndex (fun x -> x > 9) a}"
  let sorted = Array.sort a
  println $"{Array.binarySearch 4 sorted} {Array.binarySearch 6 sorted} {Array.binarySearch 1 [| 1 |]} {Array.binarySearch 1 [||]}"
  let m = Map.ofList [ ("a", 1); ("b", 2) ]
  let bump (v: option<int>) = Some(Option.defaultValue 0 v + 10)
  println $"{Map.toList (Map.change "a" bump m)} {Map.toList (Map.change "c" bump m)} {Map.toList (Map.change "b" (fun _ -> None) m)}"
  let small = Set.ofList [ 1; 2 ]
  let big = Set.ofList [ 1; 2; 3 ]
  println $"{Set.isSubset small big} {Set.isSubset big small} {Set.isSuperset big small} {Set.isSubset small small}"
  // a queue: first in, first out
  let mutable q = Queue.empty
  for i in 1 .. 3 do
    q <- Queue.enqueue i q
  let out = Buffer.empty
  let mutable going = true
  while going do
    match Queue.dequeue q with
    | Some(x, rest) ->
      Buffer.push x out
      q <- if x = 1 then Queue.enqueue 4 rest else rest
    | None -> going <- false
  println $"queue {Array.toList (Buffer.toArray out)} {Queue.count q}"
  // a stack: last in, first out
  let s = Stack.push 3 (Stack.push 2 (Stack.push 1 Stack.empty))
  match Stack.pop s with
  | Some(top, rest) -> println $"stack {top} {Stack.peek rest} {Stack.count rest}"
  | None -> ()
  // a priority queue: lowest first, and a lot of items through it in place
  let mutable pq = PriorityQueue.empty
  for (item, p) in [ ("write", 3); ("plan", 1); ("test", 4); ("code", 2) ] do
    pq <- PriorityQueue.enqueue item p pq
  let order = Buffer.empty
  let mutable more = true
  while more do
    match PriorityQueue.dequeue pq with
    | Some((item, _), rest) ->
      Buffer.push item order
      pq <- rest
    | None -> more <- false
  println $"priority {Array.toList (Buffer.toArray order)}"
  let r = Random.create (u64 1)
  let mutable heap = PriorityQueue.empty
  for i in 1 .. 200000 do
    heap <- PriorityQueue.enqueue i (Random.nextInt 0 1000000 r) heap
  let mutable last = -1
  let mutable inOrder = true
  for _ in 1 .. 200000 do
    match PriorityQueue.dequeue heap with
    | Some((_, p), rest) ->
      if p < last then
        inOrder <- false
      last <- p
      heap <- rest
    | None -> inOrder <- false
  println $"200000 in order {inOrder} {PriorityQueue.count heap}"
  0
