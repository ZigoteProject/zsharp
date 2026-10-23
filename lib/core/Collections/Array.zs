/// Functions on arrays: fixed-size sequences with constant-time indexing (`a.[i]`), written
/// `[| 1; 2; 3 |]`. Arrays are values, copied when changed (in place when nothing else refers
/// to the original).
module Collections.Array

/// An array of `n` elements: `[| f 0; …; f (n - 1) |]`.
let init n f =
  if n <= 0 then [||]
  else
    let mutable a = Array.create n (f 0)
    for i in 1 .. n - 1 do
      a.[i] <- f i
    a

// The functions that read an array take a span (an array, a Buffer, or a slice of one, with
// nothing written: `Array.sum b.[2..]`).

/// A new array with `f` applied to every element.
let map f (a: span<'a>) = Array.init (Array.length a) (fun i -> f a.[i])

/// Calls `f` on every element, in order.
let iter f (a: span<'a>) =
  for i in 0 .. Array.length a - 1 do
    f a.[i]

/// Combines the elements from the left, like `List.fold`.
let fold f state (a: span<'a>) =
  let mutable acc = state
  for i in 0 .. Array.length a - 1 do
    acc <- f acc a.[i]
  acc

/// The sum of the elements (`Add.zero` for an empty array).
let sum (a: span<'a>) = Array.fold (fun acc x -> acc + x) Add.zero a

/// An array with the list's elements, in order.
let ofList xs =
  match xs with
  | [] -> [||]
  | x :: _ ->
    let mutable a = Array.create (List.length xs) x
    let mutable cur = xs
    let mutable i = 0
    while i < Array.length a do
      match cur with
      | y :: rest ->
        a.[i] <- y
        cur <- rest
      | [] -> ()
      i <- i + 1
    a

/// A list with the array's elements, in order.
let toList (a: span<'a>) =
  let rec go acc i =
    if i < 0 then acc else go (a.[i] :: acc) (i - 1)
  go [] (Array.length a - 1)

/// Like `Array.map`, with each element's index: `f i x`.
let mapi f (a: span<'a>) = Array.init (Array.length a) (fun i -> f i a.[i])

/// Whether `f` is true for some element.
let exists f (a: span<'a>) =
  let mutable i = 0
  let mutable found = false
  while not found && i < Array.length a do
    found <- f a.[i]
    i <- i + 1
  found

/// Whether the array contains `x` (compared with `=`).
let contains x (a: span<'a>) = Array.exists (fun y -> y = x) a

/// A new array with the elements for which `f` is true.
let filter f (a: span<'a>) = Array.ofList (List.filter f (Array.toList a))

/// A new array with the elements of `a` followed by those of `b`.
let append a b = Array.ofList (List.append (Array.toList a) (Array.toList b))

/// One array with the elements of each array in the list, in order.
let concat (arrays: list<array<'a>>) : array<'a> =
  match List.filter (fun p -> Array.length p > 0) arrays with
  | [] -> [||]
  | first :: _ as parts ->
    let total = List.fold (fun n p -> n + Array.length p) 0 parts
    let mutable result = Array.create total first.[0]
    let mutable pos = 0
    for p in parts do
      for j in 0 .. Array.length p - 1 do
        result.[pos] <- p.[j]
        pos <- pos + 1
    result

/// A new array of `len` elements starting at index `start`.
let sub a start len = Array.init len (fun i -> a.[start + i])

/// A new array in reverse order.
let rev (a: span<'a>) = Array.init (Array.length a) (fun i -> a.[Array.length a - 1 - i])

/// A new array sorted in ascending order. Stable.
let sort (a: span<'a>) = Array.ofList (List.sort (Array.toList a))

/// A new array sorted with `f` (like `compare`). Stable.
let sortWith f (a: span<'a>) = Array.ofList (List.sortWith f (Array.toList a))

type array<'a> with
  /// The number of elements.
  member a.Length = Array.length a

/// The elements of a collection in an array, in its order: a list, a set, a string's
/// characters, …
let ofIter (c: 'c) : array<'a> = Array.ofList (List.ofIter c)

/// An array's elements, by index.
impl Iter<array<'a>, 'a> =
  let forEach (a: array<'a>) f =
    let n = Array.length a
    let mutable i = 0
    let mutable ok = true
    while ok && i < n do
      ok <- f a.[i]
      i <- i + 1
    ok
