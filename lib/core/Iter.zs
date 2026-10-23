/// Functions over any collection with an `Iter` impl (0017): a list, an array, a Buffer, a span,
/// a string, an option, a `Seq`, a `Range`, or a type of the program's own. `for x in c do`
/// walks one too. Each calls the impl's `forEach`, so a function here is one loop.
module Iter

/// Calls `f` on each element, in order.
let iter (f: 'a -> unit) (c: 'c) : unit =
  forEach c (fun x ->
    f x
    true)
  |> ignore

/// Combines the elements from the left: `f (f (f s x0) x1) x2`.
let fold (f: 's -> 'a -> 's) (s: 's) (c: 'c) : 's =
  let acc = ref s
  forEach c (fun x ->
    acc.Value <- f acc.Value x
    true)
  |> ignore
  acc.Value

/// Whether `p` holds for some element; stops at the first.
let exists (p: 'a -> bool) (c: 'c) : bool = not (forEach c (fun x -> not (p x)))

/// Whether `p` holds for every element; stops at the first that it doesn't.
let forall (p: 'a -> bool) (c: 'c) : bool = forEach c p

/// The first element `p` holds for.
let tryFind (p: 'a -> bool) (c: 'c) : option<'a> =
  let hit = ref None
  forEach c (fun x ->
    if p x then
      hit.Value <- Some x
      false
    else
      true)
  |> ignore
  hit.Value

/// How many elements there are.
let length (c: 'c) : int = fold (fun n _ -> n + 1) 0 c

/// The elements in a list, in order.
let toList (c: 'c) : list<'a> = List.rev (fold (fun acc x -> x :: acc) [] c)

/// The integers `start`, `start + step`, … up to `stop` (included when a step reaches it), or
/// down to it for a negative step: `{ start = 10; stop = 0; step = -2 }`.
type Range = { start: int; stop: int; step: int }

/// A range's integers, counted.
impl Iter<Range, int> =
  let forEach (r: Range) f =
    let mutable i = r.start
    let mutable ok = true
    while ok && (if r.step > 0 then i <= r.stop else i >= r.stop) do
      ok <- f i
      i <- i + r.step
    ok
