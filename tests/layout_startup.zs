// a top-level assert that isn't on constants is checked at startup, in declaration order
let items = [ 1; 2 ]
assert (List.length items = 3)

let main () =
  println "not reached"
  0
