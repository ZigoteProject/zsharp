// F#: try/with; Z#'s errors are results to match on, or Throw effects caught into results
let main () =
  try
    String.parseInt "x"
  with e ->
    0
