// A when guard performs nothing: an effect in one is an error at the call
effect Stop =
  abstract stop : string -> 'a

let positive (x: int) : bool / Stop = if x > 0 then true else Stop.stop "negative"

let f (x: int) : int / Stop =
  match x with
  | y when positive y -> 1
  | _ -> 0

let main () =
  let r =
    handle f 4 with
    | Stop.stop _, _ -> 0
  println $"{r}"
