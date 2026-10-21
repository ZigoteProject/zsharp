// A program of several files is built as one LLVM module per file, each compiled on its own:
// a case without fields (a static cell, told apart by its address) made in one module is
// matched in another, an option's None too, and a top-level value is the same in both.
open Trees

let named (o: option<string>) =
  match o with
  | Some s -> s
  | None -> "none"

let main () =
  let t = List.fold (fun acc x -> insert x acc) Leaf [ 5; 2; 8 ]
  println $"{size t} {isLeaf Leaf} {isLeaf t} {isLeaf (insert 1 Leaf)}"
  println $"{named (lookup "a")} {named (lookup "z")} {lookup "z" = None}"
  println $"{names} {firstName ()} {List.head names = firstName ()}"
  0
