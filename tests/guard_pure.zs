// A when guard in a function with effects calls pure functions, recursive ones too: they
// perform nothing there
effect Stop =
  abstract stop : string -> 'a

let rec private deep (t: int) : bool = if t > 100 then t > 200 else deep (t + 7)

let rec private even (n: int) : bool = if n = 0 then true else odd (n - 1)
and private odd (n: int) : bool = if n = 0 then false else even (n - 1)

let f (x: int) : int / Stop =
  match x with
  | y when deep y -> 1
  | y when even y -> 2
  | _ -> Stop.stop "odd"

let main () =
  let r =
    handle f 4 with
    | Stop.stop _, _ -> 0
  let s =
    handle f 3 with
    | Stop.stop _, _ -> 0
  println $"{r} {s}"
