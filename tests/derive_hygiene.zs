// A program's own `show` / `compare` doesn't capture the ones the derives call.
type P = { x: int; label: string }

let show (p: P) = "custom " + p.label
let compare (a: int) (b: int) = 42

let main () =
  let p = { x = 1; label = "a" }
  println (show p)
  println $"{p} {Some p}"
  println $"{[ Ok 1; Error "e" ]}"
  println $"{p < { x = 2; label = "a" }}"
  0
