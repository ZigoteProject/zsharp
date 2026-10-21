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

/// A new array with `f` applied to every element.
let map f a = Array.init (Array.length a) (fun i -> f a.[i])

/// Calls `f` on every element, in order.
let iter f a =
  for i in 0 .. Array.length a - 1 do
    f a.[i]

/// Combines the elements from the left, like `List.fold`.
let fold f state a =
  let mutable acc = state
  for i in 0 .. Array.length a - 1 do
    acc <- f acc a.[i]
  acc

/// The sum of the elements (`Add.zero` for an empty array).
let sum a = Array.fold (fun acc x -> acc + x) Add.zero a

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
let toList a =
  let rec go acc i =
    if i < 0 then acc else go (a.[i] :: acc) (i - 1)
  go [] (Array.length a - 1)

/// A new array with the same elements.
let copy a = Array.init (Array.length a) (fun i -> a.[i])

/// Like `Array.map`, with each element's index: `f i x`.
let mapi f a = Array.init (Array.length a) (fun i -> f i a.[i])

/// Whether `f` is true for some element.
let exists f a = List.exists f (Array.toList a)

/// Whether the array contains `x` (compared with `=`).
let contains x a = Array.exists (fun y -> y = x) a

/// A new array with the elements for which `f` is true.
let filter f a = Array.ofList (List.filter f (Array.toList a))

/// A new array with the elements of `a` followed by those of `b`.
let append a b = Array.ofList (List.append (Array.toList a) (Array.toList b))

/// A new array of `len` elements starting at index `start`.
let sub a start len = Array.init len (fun i -> a.[start + i])

/// A new array in reverse order.
let rev a = Array.init (Array.length a) (fun i -> a.[Array.length a - 1 - i])

/// A new array sorted in ascending order. Stable.
let sort a = Array.ofList (List.sort (Array.toList a))

/// A new array sorted with `f` (like `compare`). Stable.
let sortWith f a = Array.ofList (List.sortWith f (Array.toList a))

type array<'a> with
  /// The number of elements.
  member a.Length = Array.length a
