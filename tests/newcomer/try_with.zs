// F#: try/with; Z# has no exceptions, so errors are results to match on
let main () =
  try
    String.parseInt "x"
  with e ->
    0
