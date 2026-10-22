let main () =
  let a = [| 1; 2; 3; 4; 5; 6 |]
  println "before"
  let s = a.[4..9]
  println $"{Span.length s}"
  0
