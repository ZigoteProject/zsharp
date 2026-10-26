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

/// The elements grouped by `f`'s key for each, in the order the keys first appear (`'k` with
/// `Hash` and `Eq`).
let groupBy (f: 'a -> 'k) (a: span<'a>) : array<'k * array<'a>> =
  Array.ofList (List.map (fun (k, g) -> (k, Array.ofList g)) (List.groupBy f (Array.toList a)))

/// How many elements have each of `f`'s keys, in the order the keys first appear.
let countBy (f: 'a -> 'k) (a: span<'a>) : array<'k * int> =
  Array.ofList (List.countBy f (Array.toList a))

/// The elements in arrays of `size` (the last one shorter when they don't divide evenly).
let chunkBySize (size: int) (a: span<'a>) : array<array<'a>> =
  if size <= 0 then
    panic $"Array.chunkBySize: the size must be positive, not {size}"
  let n = Array.length a
  Array.init ((n + size - 1) / size) (fun c ->
    Array.init (min size (n - c * size)) (fun i -> a.[c * size + i]))

/// Every run of `size` neighbors, sliding by one (none when the array is shorter).
let windowed (size: int) (a: span<'a>) : array<array<'a>> =
  if size <= 0 then
    panic $"Array.windowed: the size must be positive, not {size}"
  Array.init (max 0 (Array.length a - size + 1)) (fun w -> Array.init size (fun i -> a.[w + i]))

/// Each element with the next.
let pairwise (a: span<'a>) : array<'a * 'a> =
  Array.init (max 0 (Array.length a - 1)) (fun i -> (a.[i], a.[i + 1]))

/// `fold`'s states, the first one and the one after each element.
let scan (f: 's -> 'a -> 's) (state: 's) (a: span<'a>) : array<'s> =
  Array.ofList (List.scan f state (Array.toList a))

/// `fold` from the back: `f a.[0] (f a.[1] (… (f a.[n - 1] state)))`.
let foldBack (f: 'a -> 's -> 's) (a: span<'a>) (state: 's) : 's =
  let mutable acc = state
  for k in 0 .. Array.length a - 1 do
    acc <- f a.[Array.length a - 1 - k] acc
  acc

/// The index of the first element for which `f` is true, or `None`.
let tryFindIndex (f: 'a -> bool) (a: span<'a>) : option<int> =
  let mutable i = 0
  let mutable found = None
  while Option.isNone found && i < Array.length a do
    if f a.[i] then
      found <- Some i
    i <- i + 1
  found

/// The index of an element equal to `x` in a sorted array, or `None`: halving the range each step.
let binarySearch (x: 'a) (a: span<'a>) : option<int> =
  let mutable lo = 0
  let mutable hi = Array.length a
  let mutable found = None
  while Option.isNone found && lo < hi do
    let mid = lo + (hi - lo) / 2
    let c = compare a.[mid] x
    if c = 0 then
      found <- Some mid
    else if c < 0 then
      lo <- mid + 1
    else
      hi <- mid
  found

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

/// The first index where two arrays differ (`.[2]: 3 vs 4`), or their lengths.
impl Diff<array<'a>> =
  let diff (a: array<'a>) (b: array<'a>) =
    let n = min (Array.length a) (Array.length b)
    let mutable i = 0
    let mutable found = None
    while Option.isNone found && i < n do
      let at = i
      found <- Option.map (fun rest -> $".[{at}]" + rest) (diff a.[i] b.[i])
      i <- i + 1
    match found with
    | Some _ -> found
    | None when Array.length a <> Array.length b ->
      Some($": {Array.length a} elements vs {Array.length b}")
    | None -> None

// last: max and min would hide the prelude's max a b and min a b from the functions above

/// The sum of `f x` over the elements.
let sumBy f (a: span<'a>) = Array.fold (fun acc x -> acc + f x) Add.zero a

// the element whose key `f` gives wins over each before it (`better new old`); panics when there's none
let private best (what: string) (better: 'k -> 'k -> bool) (f: 'a -> 'k) (a: span<'a>) : 'a =
  if Array.length a = 0 then
    panic $"Array.{what} of an empty array"
  let mutable top = a.[0]
  let mutable key = f top
  for i in 1 .. Array.length a - 1 do
    let k = f a.[i]
    if better k key then
      top <- a.[i]
      key <- k
  top

/// The largest element. Panics on an empty array.
let max (a: span<'a>) = best "max" (fun x y -> x > y) (fun x -> x) a

/// The smallest element. Panics on an empty array.
let min (a: span<'a>) = best "min" (fun x y -> x < y) (fun x -> x) a

/// The element whose `f x` is largest, the first of equals. Panics on an empty array.
///
/// ```zsharp
/// let words = [| "fig"; "banana"; "kiwi" |]
/// println $"{Array.maxBy String.length words} {Array.minBy String.length words} {Array.max [| 3; 9; 2 |]}"
/// // => banana fig 9
/// ```
let maxBy f (a: span<'a>) = best "maxBy" (fun x y -> x > y) f a

/// The element whose `f x` is smallest, the first of equals. Panics on an empty array.
let minBy f (a: span<'a>) = best "minBy" (fun x y -> x < y) f a
