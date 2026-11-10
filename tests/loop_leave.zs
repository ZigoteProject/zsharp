// break, continue and return (proposal 0029): a loop left early, a function left early
let firstError (lines: list<string>) : result<int, string> =
  let mutable total = 0
  for line in lines do
    if line = "" then continue
    if line = "end" then break
    match Int.parse line with
    | Some n -> total <- total + n
    | None -> return Error $"not a number: {line}"
  Ok total

let find (xs: array<int>) (x: int) : option<int> =
  for i in 0 .. Array.length xs - 1 do
    if xs.[i] = x then return Some i
  None

// a let's value that leaves, and a return where the function's value is wanted
let half (o: option<int>) : int =
  let n =
    match o with
    | Some n -> n
    | None -> return -1
  if n % 2 = 1 then return 0
  n / 2

let countdown (from: int) : list<int> =
  let mutable out = []
  let mutable i = from
  while true do
    if i = 0 then break
    i <- i - 1
    if i % 2 = 0 then continue
    out <- i :: out
  List.rev out

// ? in a loop's body returns the failure from the function
let number (s: string) : result<int, string> =
  match Int.parse s with
  | Some n -> Ok n
  | None -> Error $"not a number: {s}"

let sum (lines: list<string>) : result<int, string> =
  let mutable total = 0
  for line in lines do
    if line = "" then continue
    let n = number line?
    total <- total + n
  Ok total

let firstTwo (xs: list<option<int>>) : option<int> =
  let mutable acc = 0
  let mutable seen = 0
  while seen < 2 do
    let x = List.item seen xs?
    acc <- acc + x
    seen <- seen + 1
  Some acc

// two loops deep: the pair found, or none
let pair (xs: list<int>) (sum: int) : option<int * int> =
  for a in xs do
    for b in xs do
      if a < b && a + b = sum then return Some(a, b)
  None

// a range loop left early: counting down, by a step, and to its type's last value
let ranges () : string =
  let mutable s = ""
  for i in 10 .. -3 .. 0 do
    if i < 4 then break
    s <- s + $"{i} "
  for i in 0 .. 2 .. 100 do
    if i = 4 then continue
    if i > 8 then break
    s <- s + $"{i} "
  let last : u8 = 255
  for b in u8 250 .. last do
    if b = u8 252 then continue
    s <- s + $"{b} "
    if b = last then break
  s

// a lambda is its own function: return leaves it
let evens (xs: list<int>) : list<int> =
  xs |> List.filter (fun x ->
    if x < 0 then return false
    x % 2 = 0)

let log (xs: list<int>) : unit =
  for x in xs do
    if x > 2 then return
    println $"log {x}"
  println "all logged"

let main () =
  println $"{firstError [ "1"; ""; "2"; "end"; "x" ]} {firstError [ "1"; "x" ]} {firstError []}"
  println $"{find [| 5; 6; 7 |] 7} {find [| 5; 6; 7 |] 8} {find [||] 1}"
  println $"{half (Some 10)} {half (Some 3)} {half None}"
  println $"{countdown 7}"
  println $"{sum [ "1"; ""; "2" ]} {sum [ "1"; "x"; "2" ]} {firstTwo [ Some 1; Some 2; None ]} {firstTwo [ Some 1; None ]}"
  println $"{pair [ 1; 2; 3; 4 ] 7} {pair [ 1; 2 ] 9}"
  println (ranges ())
  println $"{evens [ 4; -2; 3; 6 ]}"
  log [ 1; 2; 3; 4 ]
  log [ 1 ]
  for (k, v) in Map.ofList [ (1, "a"); (2, "b"); (3, "c") ] do
    if k = 2 then continue
    println $"{k} {v}"
  for c in "abcdef" do
    if c = 'd' then break
    println $"{c}"
