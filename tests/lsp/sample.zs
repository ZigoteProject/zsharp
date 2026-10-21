// used by session.sh
let add a b = a + b

let main () =
  let total = add 1 2
  let names = [ "a"; "b" ]
  let n = names.Length
  println $"{total} {List.length names} {n}"
  0
