// Phase 2 exit test: persistent red-black tree (Okasaki), 1M inserts and lookups
type Color =
  | R
  | B

type Tree<'a> =
  | E
  | T of Color * Tree<'a> * 'a * Tree<'a>

let balance color left value right =
  match (color, left, value, right) with
  | (B, T (R, T (R, a, x, b), y, c), z, d)
  | (B, T (R, a, x, T (R, b, y, c)), z, d)
  | (B, a, x, T (R, T (R, b, y, c), z, d))
  | (B, a, x, T (R, b, y, T (R, c, z, d))) -> T (R, T (B, a, x, b), y, T (B, c, z, d))
  | (c, l, v, r) -> T (c, l, v, r)

let insert x tree =
  let rec ins t =
    match t with
    | E -> T (R, E, x, E)
    | T (c, l, y, r) ->
        if x < y then balance c (ins l) y r
        else if x > y then balance c l y (ins r)
        else t
  match ins tree with
  | T (_, l, y, r) -> T (B, l, y, r)
  | E -> E

let rec contains x t =
  match t with
  | E -> false
  | T (_, l, y, r) -> if x < y then contains x l else if x > y then contains x r else true

let rec size t =
  match t with
  | E -> 0
  | T (_, l, _, r) -> size l + 1 + size r

let rec depth t =
  match t with
  | E -> 0
  | T (_, l, _, r) -> 1 + max (depth l) (depth r)

let key i = (i * 7919) % 1000003

let rec build i n t = if i > n then t else build (i + 1) n (insert (key i) t)

let main () =
  let n = 1000000
  let t = build 1 n E
  let mutable found = 0
  for i in 1 .. n do
    if contains (key i) t then found <- found + 1
  let mutable missing = 0
  for i in 1 .. 1000 do
    if contains (1000003 + i) t then missing <- missing + 1
  println $"size {size t}, found {found}, missing {missing}, balanced {depth t <= 40}"
  // persistence: inserting into t leaves t unchanged
  let t2 = insert (-1) t
  println $"persistent {size t} {size t2} {contains (-1) t} {contains (-1) t2}"
  // the same code instantiated at another key type
  let s = insert "b" (insert "a" (insert "b" E))
  let hasA = contains "a" s
  println $"strings {size s} {hasA}"
  0
