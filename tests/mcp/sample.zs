// used by session.sh
let square x = x * x

let main () =
  let xs = List.map square [ 1; 2; 3 ]
  println $"{xs}"
  0
