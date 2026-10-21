(* Binary trees (the Benchmarks Game): allocating and walking many small trees, with the GC. *)
type tree = Leaf | Node of tree * tree

let rec make d = if d = 0 then Node (Leaf, Leaf) else Node (make (d - 1), make (d - 1))

let rec check = function Leaf -> 0 | Node (l, r) -> 1 + check l + check r

let () =
  let n = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 16 in
  let max_depth = max 6 n in
  let stretch = max_depth + 1 in
  Printf.printf "stretch tree of depth %d\t check: %d\n" stretch (check (make stretch));
  let long_lived = make max_depth in
  let d = ref 4 in
  while !d <= max_depth do
    let iterations = 1 lsl (max_depth - !d + 4) in
    let total = ref 0 in
    for _ = 1 to iterations do
      total := !total + check (make !d)
    done;
    Printf.printf "%d\t trees of depth %d\t check: %d\n" iterations !d !total;
    d := !d + 2
  done;
  Printf.printf "long lived tree of depth %d\t check: %d\n" max_depth (check long_lived)
