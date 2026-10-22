let main () =
  let f: fixed<int, 4> = Fixed.ofArray [| 1; 2; 3 |]
  println $"{f}"
  0
