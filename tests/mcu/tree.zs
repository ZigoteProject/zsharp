// a union with a case holding a list of itself, on a Cortex-M0+: its drop function's last call
// is a plain call there (Thumb1 can't tail-call another function), a loop on the other chips;
// the image didn't build for the M0+ before
type Tree =
  | Leaf of string * string
  | Node of string * list<Tree>
let main () =
  let t = Node("r", [ Leaf("a", "b") ])
  match t with
  | Node(n, kids) -> println $"{n} {List.length kids}"
  | Leaf _ -> ()
  0
