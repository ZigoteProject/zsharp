// What an if or a match finds out about a let mutable holds only until it's assigned: a test
// after the assignment runs, rather than taking the case the first test took. A bool tested in
// its own if, an option in its own match, a flag a loop tests and sets, and the same in the
// copies Simplify makes (a lambda applied twice, a case of case), whose mutables are renamed
let check (header: bool) (signature: bool) : string =
  let mutable valid = header
  if valid then
    valid <- signature
    if valid then "accepted" else "rejected"
  else
    valid <- not signature
    if valid then "retried" else "refused"

let drain (start: option<string>) : string =
  let mutable state = start
  match state with
  | Some s ->
    state <- None
    match state with
    | Some t -> $"still {t} after {s}"
    | None -> $"drained {s}"
  | None -> "empty"

let allPositive (xs: array<int>) : bool =
  let mutable ok = Array.length xs > 0
  if ok then
    for i in 0 .. Array.length xs - 1 do
      if ok then ok <- xs.[i] > 0
  ok

let twice (a: bool) (b: bool) : int =
  let step = fun (first: bool) ->
    let mutable v = first
    if v then
      v <- not v
      if v then 1 else 2
    else 3
  step a * 10 + step b

let pick (c: bool) (d: bool) : int =
  match (if c then Some true else if d then Some true else None) with
  | Some n ->
    let mutable v = n
    if v then
      v <- false
      if v then 1 else 2
    else 3
  | None -> 0

let main () =
  let yes = List.isEmpty (Environment.args ())
  let no = not yes
  println $"{check yes no} {check no no} {check yes yes}"
  let x = Some "x"
  println $"{drain x} {drain None}"
  println $"{allPositive [| 1; -1; 2 |]} {allPositive [| 1; 2 |]}"
  println $"{twice yes no} {pick yes no} {pick no yes} {pick no no}"
  0
