// Phase 2: first-class functions, closures, partial application, local functions, generics
let add x y = x + y
let twice f x = f (f x)
let compose f g x = g (f x)

let makeCounter start =
  let count = ref start
  fun () ->
    count.Value <- count.Value + 1
    count.Value

let rec sumTo acc n = if n = 0 then acc else sumTo (acc + n) (n - 1)

let pairUp x = (x, x)

let main () =
  let inc = add 1
  println $"inc 41 = {inc 41}"
  println $"twice inc 5 = {twice inc 5}"
  let square = fun x -> x * x
  println $"compose = {compose inc square 3}"
  println $"pipeline = {[1; 2; 3; 4] |> List.map (fun x -> x * 10) |> List.filter (fun x -> x > 15) |> List.sum}"
  let shout = (fun s -> s + "!") >> (fun s -> s + "?")
  println (shout "hey")
  let next = makeCounter 10
  next () |> ignore
  println $"counter = {next ()}"
  let offset = 100
  let rec countDown n acc = if n = 0 then acc else countDown (n - 1) (acc + offset)
  println $"local rec = {countDown 5 0}"
  println $"tail calls = {sumTo 0 1000000}"
  let (a, b) = pairUp "same"
  let (c, d) = pairUp 2.5
  println $"generic = {a}{b} {c + d}"
  let adders = List.map add [ 1; 2; 3 ]
  println $"adders = {List.map (fun f -> f 10) adders |> List.sum}"
  0
