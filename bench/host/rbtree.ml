(* A red-black tree (Okasaki's): inserting a million keys into a persistent tree, then looking
   each one up. The same algorithm as the Z# version, so the GC meets Perceus. *)
type color = Red | Black
type tree = Empty | Node of color * tree * int * tree

let balance c l k r =
  match (c, l, k, r) with
  | Black, Node (Red, Node (Red, a, x, b), y, c2), z, d
  | Black, Node (Red, a, x, Node (Red, b, y, c2)), z, d
  | Black, a, x, Node (Red, Node (Red, b, y, c2), z, d)
  | Black, a, x, Node (Red, b, y, Node (Red, c2, z, d)) ->
      Node (Red, Node (Black, a, x, b), y, Node (Black, c2, z, d))
  | _ -> Node (c, l, k, r)

let insert k t =
  let rec ins t =
    match t with
    | Empty -> Node (Red, Empty, k, Empty)
    | Node (c, l, x, r) -> if k < x then balance c (ins l) x r else if k > x then balance c l x (ins r) else t
  in
  match ins t with Node (_, l, x, r) -> Node (Black, l, x, r) | Empty -> Empty

let rec contains k = function
  | Empty -> false
  | Node (_, l, x, r) -> if k < x then contains k l else if k > x then contains k r else true

let () =
  let n = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 1000000 in
  let t = ref Empty and seed = ref 42 in
  for _ = 1 to n do
    seed := ((!seed * 1103515245) + 12345) mod 2147483648;
    t := insert (!seed mod n) !t
  done;
  let found = ref 0 in
  for i = 0 to n - 1 do
    if contains i !t then incr found
  done;
  Printf.printf "%d\n" !found
