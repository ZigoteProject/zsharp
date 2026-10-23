// Generators: seq { } and the Seq functions, consumed by handlers of Yield (phase 10)

let evens n = seq { for i in 1 .. n do if i % 2 = 0 then yield i }

// a generator written as a function: its type says it yields (unit -> unit / Yield<int>)
let countdown n =
  let mutable i = n
  while i > 0 do
    Yield.yield i
    i <- i - 1

type Rose = Rose of int * list<Rose>

// a recursive generator: each node, then its children
let rec preorder (t: Rose) =
  match t with
  | Rose(v, kids) ->
    Yield.yield v
    for k in kids do preorder k

let main () =
  println $"{evens 100 |> Seq.map (fun x -> x * x) |> Seq.take 3 |> Seq.toList}"
  println $"{Seq.sum (evens 10)}"
  let mutable total = 0
  for x in evens 10 do total <- total + x
  println $"{total}"
  let nested =
    seq {
      yield 0
      yield! evens 6
      yield 100 }
  println $"{Seq.toList nested}"
  println $"{Seq.toList (Seq(fun () -> countdown 3))}"
  let naturals = Seq.unfold (fun n -> Some(n, n + 1)) 0
  println $"{naturals |> Seq.filter (fun n -> n % 7 = 0) |> Seq.skip 1 |> Seq.take 4 |> Seq.toList}"
  println $"{Seq.exists (fun n -> n > 1000) naturals} {Seq.forall (fun n -> n < 10) naturals}"
  println $"{Seq.tryFind (fun n -> n * n > 50) naturals} {Seq.tryHead (Seq.empty ())}"
  println $"{Seq.length (Seq.ofList [ 1; 2; 3 ])} {Seq.isEmpty (Seq.empty ())} {Seq.toList (Seq.indexed (Seq.ofArray [| 'a'; 'b' |]))}"
  println $"{Seq.toList (Seq.collect (fun n -> Seq.init n (fun i -> n * 10 + i)) (Seq.ofList [ 1; 2; 3 ]))}"
  println $"{Seq.toList (Seq.append (Seq.singleton 1) (Seq.takeWhile (fun x -> x < 4) naturals))}"
  println $"{Seq.toList (Seq.choose (fun x -> if x % 3 = 0 then Some(x / 3) else None) (Seq.take 10 naturals))}"
  let digits = Seq.fold (fun acc x -> acc + string x) "" (Seq.take 5 naturals)
  println digits
  // a long one: each stage handles Yield right where the generator performs it
  println $"{Seq.sum (Seq.take 1000000 naturals)}"
  let tree = Rose(1, [ Rose(2, [ Rose(3, []) ]); Rose(4, []) ])
  println $"{Seq.toList (Seq(fun () -> preorder tree))}"
  let seen = ref []
  Seq.iteri (fun i x -> seen.Value <- (i, x) :: seen.Value) (evens 6)
  println $"{List.rev seen.Value}"
  0
