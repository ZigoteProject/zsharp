/// Functions on lists, immutable singly linked lists: `[ 1; 2; 3 ]`, `x :: rest`. They are
/// tail-recursive (loops after compilation), so long lists don't exhaust the stack.
module Collections.List

// ponytail: map/filter build reversed then List.rev; tail recursion modulo cons would save the pass

/// The list in reverse order. Reuses the cells when the list is unique.
let rev xs =
  let rec go acc xs =
    match xs with
    | [] -> acc
    | x :: rest -> go (x :: acc) rest
  go [] xs

/// The number of elements. O(n).
let length xs =
  let rec go n xs =
    match xs with
    | [] -> n
    | _ :: rest -> go (n + 1) rest
  go 0 xs

/// Whether the list has no elements.
let isEmpty xs =
  match xs with
  | [] -> true
  | _ -> false

/// The first element. Panics on an empty list; see `List.tryHead`.
let head xs =
  match xs with
  | x :: _ -> x
  | [] -> panic "List.head: empty list"

/// Everything after the first element. Panics on an empty list.
let tail xs =
  match xs with
  | _ :: rest -> rest
  | [] -> panic "List.tail: empty list"

/// Applies `f` to every element: `List.map f [a; b] = [f a; f b]`.
let map f xs =
  let rec go acc xs =
    match xs with
    | [] -> List.rev acc
    | x :: rest -> go (f x :: acc) rest
  go [] xs

/// The elements for which `f` returns true, in order.
let filter f xs =
  let rec go acc xs =
    match xs with
    | [] -> List.rev acc
    | x :: rest -> if f x then go (x :: acc) rest else go acc rest
  go [] xs

/// Combines the elements from the left: `List.fold f s [a; b] = f (f s a) b`.
let fold f state xs =
  let rec go acc xs =
    match xs with
    | [] -> acc
    | x :: rest -> go (f acc x) rest
  go state xs

/// Calls `f` on every element, in order.
let iter f xs =
  let rec go xs =
    match xs with
    | [] -> ()
    | x :: rest ->
      f x
      go rest
  go xs

/// The elements of `xs` followed by those of `ys` (also written `xs @ ys`).
let append xs ys =
  let rec go acc xs =
    match xs with
    | [] -> acc
    | x :: rest -> go (x :: acc) rest
  go ys (List.rev xs)

/// Whether `f` is true for some element. Stops at the first.
let exists f xs =
  let rec go xs =
    match xs with
    | [] -> false
    | x :: rest -> if f x then true else go rest
  go xs

/// Whether `f` is true for every element. Stops at the first false.
let forall f xs =
  let rec go xs =
    match xs with
    | [] -> true
    | x :: rest -> if f x then go rest else false
  go xs

/// Whether the list contains `x` (compared with `=`).
let contains x xs = List.exists (fun y -> y = x) xs

/// The first element for which `f` is true, or `None`.
let tryFind f xs =
  let rec go xs =
    match xs with
    | [] -> None
    | x :: rest -> if f x then Some x else go rest
  go xs

/// The index of the first element for which `f` is true, or `None`.
let tryFindIndex f xs =
  let rec go i xs =
    match xs with
    | [] -> None
    | x :: rest -> if f x then Some i else go (i + 1) rest
  go 0 xs

/// The index of the first element for which `f` is true. Panics if there is none; see
/// `List.tryFindIndex`.
let findIndex f xs =
  match List.tryFindIndex f xs with
  | Some i -> i
  | None -> panic "List.findIndex: no element satisfies the predicate"

/// The first element for which `f` is true. Panics if there is none; see `List.tryFind`.
let find f xs =
  match List.tryFind f xs with
  | Some x -> x
  | None -> panic "List.find: no element satisfies the predicate"

/// The first `Some` result of `f` on the elements, in order, or `None`.
let tryPick f xs =
  let rec go xs =
    match xs with
    | [] -> None
    | x :: rest ->
      match f x with
      | Some y -> Some y
      | None -> go rest
  go xs

/// The sum of the elements (`Add.zero` for an empty list).
let sum xs = List.fold (fun acc x -> acc + x) Add.zero xs

/// A list of `n` elements: `[f 0; f 1; …; f (n - 1)]`.
let init n f =
  // f in index order, as F#'s (it may have effects: a generator's draws)
  let rec go acc i =
    if i >= n then List.rev acc else go (f i :: acc) (i + 1)
  go [] 0

/// A list of `n` copies of `x`.
let replicate n x = List.init n (fun _ -> x)

/// Like `List.map`, with each element's index: `f i x`.
let mapi f xs =
  let rec go acc i xs =
    match xs with
    | [] -> List.rev acc
    | x :: rest -> go (f i x :: acc) (i + 1) rest
  go [] 0 xs

/// Applies `f` to each element with its index, in order: `f i x`.
let iteri f xs =
  let rec go i xs =
    match xs with
    | [] -> ()
    | x :: rest ->
      f i x
      go (i + 1) rest
  go 0 xs

/// Each element paired with its index: `[(0, a); (1, b)]`.
let indexed xs = List.mapi (fun i x -> (i, x)) xs

/// Applies `f` to every element and keeps the values of the `Some` results.
let choose f xs =
  let rec go acc xs =
    match xs with
    | [] -> List.rev acc
    | x :: rest ->
      match f x with
      | Some y -> go (y :: acc) rest
      | None -> go acc rest
  go [] xs

/// Applies `f` to every element and concatenates the resulting lists.
let collect f xs = List.fold (fun acc x -> List.append acc (f x)) [] xs

/// The lists one after another, in one list.
let concat (xss: list<list<'a>>) = List.collect id xss

/// Pairs up the elements of two lists; stops at the end of the shorter one.
let zip xs ys =
  let rec go acc xs ys =
    match (xs, ys) with
    | (x :: xr, y :: yr) -> go ((x, y) :: acc) xr yr
    | _ -> List.rev acc
  go [] xs ys

/// Applies `f` to the elements of two lists pairwise. Panics if their lengths differ.
let map2 f xs ys =
  let rec go acc xs ys =
    match (xs, ys) with
    | (x :: xr, y :: yr) -> go (f x y :: acc) xr yr
    | ([], []) -> List.rev acc
    | _ -> panic "List.map2: the lists have different lengths"
  go [] xs ys

/// Applies `f` to the elements of two lists pairwise, in order. Panics if their lengths differ.
let iter2 f xs ys =
  let rec go xs ys =
    match (xs, ys) with
    | (x :: xr, y :: yr) ->
      f x y
      go xr yr
    | ([], []) -> ()
    | _ -> panic "List.iter2: the lists have different lengths"
  go xs ys

/// Splits a list of pairs into a pair of lists.
let unzip xs = (List.map fst xs, List.map snd xs)

/// The first element, or `None` for an empty list.
let tryHead xs =
  match xs with
  | x :: _ -> Some x
  | [] -> None

/// The last element. Panics on an empty list.
let last xs =
  let rec go x xs =
    match xs with
    | [] -> x
    | y :: rest -> go y rest
  match xs with
  | x :: rest -> go x rest
  | [] -> panic "List.last: empty list"

/// The last element, or `None` for an empty list.
let tryLast xs =
  let rec go x xs =
    match xs with
    | [] -> x
    | y :: rest -> go y rest
  match xs with
  | x :: rest -> Some(go x rest)
  | [] -> None

/// The element at index `n` (from 0). Panics if the list is too short. O(n).
let item n xs =
  let rec go i xs =
    match xs with
    | x :: rest -> if i = 0 then x else go (i - 1) rest
    | [] -> panic "List.item: index out of range"
  go n xs

/// The element at index `n` (from 0), or `None` if the list is too short.
let tryItem n xs =
  let rec go i xs =
    match xs with
    | x :: rest -> if i = 0 then Some x else go (i - 1) rest
    | [] -> None
  if n < 0 then None else go n xs

/// The list without the element at index `n` (from 0). Panics if the list is too short.
let removeAt n xs =
  let rec go acc i xs =
    match xs with
    | x :: rest -> if i = 0 then List.append (List.rev acc) rest else go (x :: acc) (i - 1) rest
    | [] -> panic "List.removeAt: index out of range"
  go [] n xs

/// The first `n` elements (fewer if the list is shorter).
let take n xs =
  let rec go acc n xs =
    if n <= 0 then List.rev acc
    else
      match xs with
      | x :: rest -> go (x :: acc) (n - 1) rest
      | [] -> List.rev acc
  go [] n xs

/// The elements before the first one for which `f` is false.
let takeWhile f xs =
  let rec go acc xs =
    match xs with
    | x :: rest -> if f x then go (x :: acc) rest else List.rev acc
    | [] -> List.rev acc
  go [] xs

/// The list without its first `n` elements.
let rec skip n xs =
  if n <= 0 then xs
  else
    match xs with
    | _ :: rest -> List.skip (n - 1) rest
    | [] -> []

/// Combines the elements from the left, starting with the first. Panics on an empty list.
let reduce f xs =
  match xs with
  | x :: rest -> List.fold f x rest
  | [] -> panic "List.reduce: empty list"

/// The elements for which `f` is true, and the others, both in order.
let partition f xs =
  let rec go yes no xs =
    match xs with
    | [] -> (List.rev yes, List.rev no)
    | x :: rest -> if f x then go (x :: yes) no rest else go yes (x :: no) rest
  go [] [] xs

/// The largest element. Panics on an empty list.
let max xs = List.reduce (fun a b -> if b > a then b else a) xs

/// The smallest element. Panics on an empty list.
let min xs = List.reduce (fun a b -> if b < a then b else a) xs

/// The sum of `f x` over the elements.
let sumBy f xs = List.fold (fun acc x -> acc + f x) Add.zero xs

// ponytail: quadratic; fine for short lists, use a hash set when one exists
/// The list without repeated elements, keeping first occurrences.
let distinct xs =
  List.rev (List.fold (fun acc x -> if List.contains x acc then acc else x :: acc) [] xs)

// stable merge sort
/// The list sorted with `cmp` (negative, zero or positive, like `compare`). Stable.
let sortWith cmp xs =
  let rec merge acc a b =
    match (a, b) with
    | ([], _) -> List.append (List.rev acc) b
    | (_, []) -> List.append (List.rev acc) a
    | (x :: xr, y :: yr) -> if cmp x y <= 0 then merge (x :: acc) xr b else merge (y :: acc) a yr
  let rec sort n xs =
    if n < 2 then xs
    else
      let half = n / 2
      merge [] (sort half (List.take half xs)) (sort (n - half) (List.skip half xs))
  sort (List.length xs) xs

/// The list sorted in ascending order. Stable.
let sort xs = List.sortWith compare xs

/// The list sorted by the key `f x`. Stable.
let sortBy f xs = List.sortWith (fun a b -> compare (f a) (f b)) xs

type list<'a> with
  /// The number of elements. O(n).
  member xs.Length = List.length xs
  /// The first element. Panics on an empty list.
  member xs.Head = List.head xs
  /// Everything after the first element. Panics on an empty list.
  member xs.Tail = List.tail xs
  /// Whether the list has no elements.
  member xs.IsEmpty = List.isEmpty xs

/// The elements of a collection, in its order: an array, a string's characters, a map's
/// entries, …
let ofIter (c: 'c) : list<'a> =
  let acc = ref []
  Iter.forEach c (fun x ->
    acc.Value <- x :: acc.Value
    true)
  |> ignore
  rev acc.Value

/// A list's elements, front to back.
impl Iter<list<'a>, 'a> =
  let forEach xs f =
    let mutable cur = xs
    let mutable more = true
    let mutable ok = true
    while ok && more do
      match cur with
      | x :: rest ->
        cur <- rest
        ok <- f x
      | [] -> more <- false
    ok

/// The first element where two lists differ (`.[2]: 3 vs 4`), or where one of them ends.
impl Diff<list<'a>> =
  let diff xs ys =
    let rec go i xs ys =
      match (xs, ys) with
      | [], [] -> None
      | x :: xs, y :: ys ->
        match diff x y with
        | Some rest -> Some($".[{i}]" + rest)
        | None -> go (i + 1) xs ys
      | _ -> Some($": {i + length xs} elements vs {i + length ys}")
    go 0 xs ys
