// `?` returns early with an Error or None, so the function must return a result or an option
let show (s: string) =
  let n = String.parseInt s?
  println $"{n}"

let main () =
  show "42"
  0
