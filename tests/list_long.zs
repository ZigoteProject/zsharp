// `=`, `compare` and `hash` on lists run in constant stack, in every build: a list of 200,001
// elements is compared and hashed, where the derived impls recursed once an element.
let main () =
  // as the derived impls gave them
  println $"{hash [ 1; 2; 3 ]} {hash ([]: list<int>)} {hash [ [ 1 ]; [] ]}"
  println $"{compare [ 1; 2 ] [ 1; 3 ]} {compare [ 2 ] [ 1; 3 ]} {compare [ 1 ] [ 1; 0 ]} {compare ([]: list<int>) []}"
  println $"{[ 1; 2 ] = [ 1; 2 ]} {[ 1; 2 ] = [ 1 ]} {[ 1; 2 ] <> [ 1; 3 ]} {[ Some 1; None ] = [ Some 1; None ]}"
  println $"{List.sort [ [ 2; 1 ]; []; [ 1; 5 ]; [ 1 ] ]}"
  let a = List.init 200001 (fun i -> i % 251)
  let b = List.init 200001 (fun i -> i % 251)
  let c = List.init 200001 (fun i -> if i = 200000 then -1 else i % 251)
  println $"{a = b} {a = c} {a <> c} {compare a b} {compare a c} {compare c a}"
  println $"{hash a = hash b} {hash a = hash c}"
  0
