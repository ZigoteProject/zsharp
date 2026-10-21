// Phase 3: the ? operator over result
let parseDigit (c: int) = if c >= 0 && c <= 9 then Ok c else Error $"not a digit: {c}"

let sum3 a b c =
  let x = parseDigit a?
  let y = parseDigit b?
  let z = parseDigit c?
  Ok (x + y + z)

let check n =
  parseDigit n?
  Ok "fine"

let show r =
  match r with
  | Ok v -> println $"ok {v}"
  | Error e -> println $"error: {e}"

let main () =
  show (sum3 1 2 3)
  show (sum3 1 42 3)
  match check 5 with
  | Ok s -> println s
  | Error e -> println e
  0
