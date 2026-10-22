// ? in a function returning unit: neither a result nor an option to return early with
let report (s: string) =
  let n = String.parseInt s?
  println $"{n}"

let main () =
  report "4"
  0
