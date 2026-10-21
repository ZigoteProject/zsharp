// Z# prelude: compiled before every program. Every item is documented with `///` comments,
// which hover, completion, `zs doc` and the MCP `docs` tool show.
// List functions are tail-recursive (loops after codegen) so long lists don't exhaust the stack.
// ponytail: map/filter build reversed then List.rev; tail recursion modulo cons would save the pass

// The operator traits below have built-in impls for the primitive types; user types implement
// them with `impl`. Eq, Ord, Hash and Show are also derived for every record and union.

/// `+` and a zero, for `List.sum`. Built in for numbers and `string` (concatenation, "").
trait Add<'a> =
  /// `a + b`.
  abstract add : 'a -> 'a -> 'a
  /// The value that `+` leaves unchanged: `0`, `0.0`, `""`.
  abstract zero : 'a

/// `-`, `*`, `/`, `%` and negation. Built in for the integer and floating-point types.
trait Num<'a> =
  /// `a - b`.
  abstract sub : 'a -> 'a -> 'a
  /// `a * b`.
  abstract mul : 'a -> 'a -> 'a
  /// `a / b`. Integer division by zero panics.
  abstract div : 'a -> 'a -> 'a
  /// `a % b`. Integer remainder by zero panics.
  abstract rem : 'a -> 'a -> 'a
  /// `-a`.
  abstract neg : 'a -> 'a

/// `=` and `<>`. Built in for primitives; derived structurally for records, unions and tuples.
trait Eq<'a> =
  /// `a = b`.
  abstract equal : 'a -> 'a -> bool

/// `<`, `>`, `<=`, `>=` and `compare`. Built in for numbers and strings; derived for records,
/// unions (by case order, then fields) and tuples (lexicographically).
trait Ord<'a> =
  /// A negative number, zero or a positive number as `a` is less than, equal to or greater than `b`.
  abstract compare : 'a -> 'a -> int

/// Text for a value: what `string x` and `$"{x}"` use. Built in for numbers, bools and
/// strings; derived for records (`{ x = 1; y = 2 }`) and unions (`Some 1`, `Rect (1, 2)`).
trait Show<'a> =
  /// The value as text.
  abstract show : 'a -> string

/// A hash code, consistent with `Eq`: equal values hash the same.
trait Hash<'a> =
  /// The value's hash code.
  abstract hash : 'a -> int

/// What `match Shape.kind with` distinguishes inside a `derive`.
type ShapeKind =
  /// The type being derived for is a record.
  | RecordKind
  /// The type being derived for is a union.
  | UnionKind

/// Structural equality for records and unions: same case and equal fields. Applied the first
/// time a type needs `=`; an explicit `impl Eq` or `[<NoEquality>]` takes precedence.
derive Eq =
  let equal (a: 'self) (b: 'self) =
    match Shape.pair a b with
    | Same c ->
      let mutable same = true
      for f in c.fields do
        if same then same <- f.left = f.right
      same
    | Different _ -> false

/// Structural ordering for records and unions: by case (in declaration order), then field by
/// field. Applied the first time a type needs it; `[<NoComparison>]` opts out.
derive Ord =
  let compare (a: 'self) (b: 'self) =
    match Shape.pair a b with
    | Same c ->
      let mutable r = 0
      for f in c.fields do
        if r = 0 then r <- compare f.left f.right
      r
    | Different (i, j) -> compare i j

/// A structural hash for records and unions, consistent with the derived `Eq`.
derive Hash =
  let hash (x: 'self) =
    match Shape.of x with
    | Record r ->
      let mutable h = 17
      for f in r.fields do
        h <- h * 31 + hash f.value
      h
    | Union c ->
      let mutable h = 17 + c.index
      for f in c.fields do
        h <- h * 31 + hash f.value
      h

/// F#-style text for records (`{ x = 1; y = 2 }`) and unions (`Leaf`, `Some 1`, `Rect (1, 2)`).
derive Show =
  let show (x: 'self) =
    match Shape.of x with
    | Record r ->
      let mutable s = "{ "
      for f in r.fields do
        s <- s + (if f.index > 0 then "; " else "") + f.name + " = " + show f.value
      s + " }"
    | Union c ->
      let mutable s = c.name
      for f in c.fields do
        s <- s + (if f.index = 0 then (if c.count > 1 then " (" else " ") else ", ") + show f.value
      if c.count > 1 then s + ")" else s

/// A value that may be missing. Use it instead of null: `Some x` or `None`.
type option<'a> =
  /// No value.
  | None
  /// A value.
  | Some of 'a

/// The outcome of something that can fail: `Ok value` or `Error err`. The `?` operator
/// returns early with the `Error`.
type result<'a, 'e> =
  /// Success, with its value.
  | Ok of 'a
  /// Failure, with its error.
  | Error of 'e

/// Returns its argument unchanged.
let id x = x
/// The first component of a pair.
let fst (a, _) = a
/// The second component of a pair.
let snd (_, b) = b
/// The larger of two values.
let max a b = if a > b then a else b
/// The smaller of two values.
let min a b = if a < b then a else b

/// The list in reverse order. Reuses the cells when the list is unique.
let List.rev xs =
  let rec go acc xs =
    match xs with
    | [] -> acc
    | x :: rest -> go (x :: acc) rest
  go [] xs

/// The number of elements. O(n).
let List.length xs =
  let rec go n xs =
    match xs with
    | [] -> n
    | _ :: rest -> go (n + 1) rest
  go 0 xs

/// Whether the list has no elements.
let List.isEmpty xs =
  match xs with
  | [] -> true
  | _ -> false

/// The first element. Panics on an empty list; see `List.tryHead`.
let List.head xs =
  match xs with
  | x :: _ -> x
  | [] -> panic "List.head: empty list"

/// Everything after the first element. Panics on an empty list.
let List.tail xs =
  match xs with
  | _ :: rest -> rest
  | [] -> panic "List.tail: empty list"

/// Applies `f` to every element: `List.map f [a; b] = [f a; f b]`.
let List.map f xs =
  let rec go acc xs =
    match xs with
    | [] -> List.rev acc
    | x :: rest -> go (f x :: acc) rest
  go [] xs

/// The elements for which `f` returns true, in order.
let List.filter f xs =
  let rec go acc xs =
    match xs with
    | [] -> List.rev acc
    | x :: rest -> if f x then go (x :: acc) rest else go acc rest
  go [] xs

/// Combines the elements from the left: `List.fold f s [a; b] = f (f s a) b`.
let List.fold f state xs =
  let rec go acc xs =
    match xs with
    | [] -> acc
    | x :: rest -> go (f acc x) rest
  go state xs

/// Calls `f` on every element, in order.
let List.iter f xs =
  let rec go xs =
    match xs with
    | [] -> ()
    | x :: rest ->
      f x
      go rest
  go xs

/// The elements of `xs` followed by those of `ys` (also written `xs @ ys`).
let List.append xs ys =
  let rec go acc xs =
    match xs with
    | [] -> acc
    | x :: rest -> go (x :: acc) rest
  go ys (List.rev xs)

/// Whether `f` is true for some element. Stops at the first.
let List.exists f xs =
  let rec go xs =
    match xs with
    | [] -> false
    | x :: rest -> if f x then true else go rest
  go xs

/// Whether `f` is true for every element. Stops at the first false.
let List.forall f xs =
  let rec go xs =
    match xs with
    | [] -> true
    | x :: rest -> if f x then go rest else false
  go xs

/// Whether the list contains `x` (compared with `=`).
let List.contains x xs = List.exists (fun y -> y = x) xs

/// The first element for which `f` is true, or `None`.
let List.tryFind f xs =
  let rec go xs =
    match xs with
    | [] -> None
    | x :: rest -> if f x then Some x else go rest
  go xs

/// The sum of the elements (`Add.zero` for an empty list).
let List.sum xs = List.fold (fun acc x -> acc + x) Add.zero xs

/// A list of `n` elements: `[f 0; f 1; …; f (n - 1)]`.
let List.init n f =
  let rec go acc i =
    if i < 0 then acc else go (f i :: acc) (i - 1)
  go [] (n - 1)

/// Applies `f` to the value of `Some`; `None` stays `None`.
let Option.map f o =
  match o with
  | Some x -> Some (f x)
  | None -> None

/// Applies `f`, which itself returns an option, to the value of `Some`.
let Option.bind f o =
  match o with
  | Some x -> f x
  | None -> None

/// The value of `Some`, or `d` for `None`.
let Option.defaultValue d o =
  match o with
  | Some x -> x
  | None -> d

/// Whether the option holds a value.
let Option.isSome o =
  match o with
  | Some _ -> true
  | None -> false

/// Whether the option is `None`.
let Option.isNone o = not (Option.isSome o)

/// The value of `Some`. Panics on `None`; prefer a match or `Option.defaultValue`.
let Option.get o =
  match o with
  | Some x -> x
  | None -> panic "Option.get: None"

/// Applies `f` to the value of `Ok`; an `Error` passes through.
let Result.map f r =
  match r with
  | Ok x -> Ok (f x)
  | Error e -> Error e

/// Applies `f`, which itself returns a result, to the value of `Ok`.
let Result.bind f r =
  match r with
  | Ok x -> f x
  | Error e -> Error e

/// An array of `n` elements: `[| f 0; …; f (n - 1) |]`.
let Array.init n f =
  if n <= 0 then [||]
  else
    let a = Array.create n (f 0)
    for i in 1 .. n - 1 do
      a.[i] <- f i
    a

/// A new array with `f` applied to every element.
let Array.map f a = Array.init (Array.length a) (fun i -> f a.[i])

/// Calls `f` on every element, in order.
let Array.iter f a =
  for i in 0 .. Array.length a - 1 do
    f a.[i]

/// Combines the elements from the left, like `List.fold`.
let Array.fold f state a =
  let mutable acc = state
  for i in 0 .. Array.length a - 1 do
    acc <- f acc a.[i]
  acc

/// The sum of the elements (`Add.zero` for an empty array).
let Array.sum a = Array.fold (fun acc x -> acc + x) Add.zero a

/// An array with the list's elements, in order.
let Array.ofList xs =
  match xs with
  | [] -> [||]
  | x :: _ ->
    let a = Array.create (List.length xs) x
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
let Array.toList a =
  let rec go acc i =
    if i < 0 then acc else go (a.[i] :: acc) (i - 1)
  go [] (Array.length a - 1)

// members on built-in types
type string with
  /// The length in bytes (UTF-8).
  member s.Length = String.length s

type array<'a> with
  /// The number of elements.
  member a.Length = Array.length a

type list<'a> with
  /// The number of elements. O(n).
  member xs.Length = List.length xs
  /// The first element. Panics on an empty list.
  member xs.Head = List.head xs
  /// Everything after the first element. Panics on an empty list.
  member xs.Tail = List.tail xs
  /// Whether the list has no elements.
  member xs.IsEmpty = List.isEmpty xs

type option<'a> with
  /// Whether the option holds a value.
  member o.IsSome = Option.isSome o
  /// Whether the option is `None`.
  member o.IsNone = Option.isNone o

/// Lists print as `[1; 2; 3]`.
impl Show<list<'a>> =
  let show xs =
    let rec go acc first xs =
      match xs with
      | [] -> acc
      | x :: rest -> go (acc + (if first then "" else "; ") + show x) false rest
    "[" + go "" true xs + "]"

// ---------------------------------------------------------------- List (more)

/// Like `List.map`, with each element's index: `f i x`.
let List.mapi f xs =
  let rec go acc i xs =
    match xs with
    | [] -> List.rev acc
    | x :: rest -> go (f i x :: acc) (i + 1) rest
  go [] 0 xs

/// Each element paired with its index: `[(0, a); (1, b)]`.
let List.indexed xs = List.mapi (fun i x -> (i, x)) xs

/// Applies `f` to every element and keeps the values of the `Some` results.
let List.choose f xs =
  let rec go acc xs =
    match xs with
    | [] -> List.rev acc
    | x :: rest ->
      match f x with
      | Some y -> go (y :: acc) rest
      | None -> go acc rest
  go [] xs

/// Applies `f` to every element and concatenates the resulting lists.
let List.collect f xs = List.fold (fun acc x -> List.append acc (f x)) [] xs

/// Pairs up the elements of two lists; stops at the end of the shorter one.
let List.zip xs ys =
  let rec go acc xs ys =
    match (xs, ys) with
    | (x :: xr, y :: yr) -> go ((x, y) :: acc) xr yr
    | _ -> List.rev acc
  go [] xs ys

/// Splits a list of pairs into a pair of lists.
let List.unzip xs = (List.map fst xs, List.map snd xs)

/// The first element, or `None` for an empty list.
let List.tryHead xs =
  match xs with
  | x :: _ -> Some x
  | [] -> None

/// The last element. Panics on an empty list.
let List.last xs =
  let rec go x xs =
    match xs with
    | [] -> x
    | y :: rest -> go y rest
  match xs with
  | x :: rest -> go x rest
  | [] -> panic "List.last: empty list"

/// The element at index `n` (from 0). Panics if the list is too short. O(n).
let List.item n xs =
  let rec go i xs =
    match xs with
    | x :: rest -> if i = 0 then x else go (i - 1) rest
    | [] -> panic "List.item: index out of range"
  go n xs

/// The first `n` elements (fewer if the list is shorter).
let List.take n xs =
  let rec go acc n xs =
    if n <= 0 then List.rev acc
    else
      match xs with
      | x :: rest -> go (x :: acc) (n - 1) rest
      | [] -> List.rev acc
  go [] n xs

/// The list without its first `n` elements.
let rec List.skip n xs =
  if n <= 0 then xs
  else
    match xs with
    | _ :: rest -> List.skip (n - 1) rest
    | [] -> []

/// Combines the elements from the left, starting with the first. Panics on an empty list.
let List.reduce f xs =
  match xs with
  | x :: rest -> List.fold f x rest
  | [] -> panic "List.reduce: empty list"

/// The elements for which `f` is true, and the others, both in order.
let List.partition f xs =
  let rec go yes no xs =
    match xs with
    | [] -> (List.rev yes, List.rev no)
    | x :: rest -> if f x then go (x :: yes) no rest else go yes (x :: no) rest
  go [] [] xs

/// The largest element. Panics on an empty list.
let List.max xs = List.reduce (fun a b -> if b > a then b else a) xs
/// The smallest element. Panics on an empty list.
let List.min xs = List.reduce (fun a b -> if b < a then b else a) xs
/// The sum of `f x` over the elements.
let List.sumBy f xs = List.fold (fun acc x -> acc + f x) Add.zero xs

// ponytail: quadratic; fine for short lists, use a hash set when one exists
/// The list without repeated elements, keeping first occurrences.
let List.distinct xs =
  List.rev (List.fold (fun acc x -> if List.contains x acc then acc else x :: acc) [] xs)

// stable merge sort
/// The list sorted with `cmp` (negative, zero or positive, like `compare`). Stable.
let List.sortWith cmp xs =
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
let List.sort xs = List.sortWith compare xs
/// The list sorted by the key `f x`. Stable.
let List.sortBy f xs = List.sortWith (fun a b -> compare (f a) (f b)) xs

// ---------------------------------------------------------------- Array (more)

/// A new array with the same elements.
let Array.copy a = Array.init (Array.length a) (fun i -> a.[i])
/// Like `Array.map`, with each element's index: `f i x`.
let Array.mapi f a = Array.init (Array.length a) (fun i -> f i a.[i])
/// Whether `f` is true for some element.
let Array.exists f a = List.exists f (Array.toList a)
/// Whether the array contains `x` (compared with `=`).
let Array.contains x a = Array.exists (fun y -> y = x) a
/// A new array with the elements for which `f` is true.
let Array.filter f a = Array.ofList (List.filter f (Array.toList a))
/// A new array with the elements of `a` followed by those of `b`.
let Array.append a b = Array.ofList (List.append (Array.toList a) (Array.toList b))
/// A new array of `len` elements starting at index `start`.
let Array.sub a start len = Array.init len (fun i -> a.[start + i])
/// A new array in reverse order.
let Array.rev a = Array.init (Array.length a) (fun i -> a.[Array.length a - 1 - i])
/// A new array sorted in ascending order. Stable.
let Array.sort a = Array.ofList (List.sort (Array.toList a))
/// A new array sorted with `f` (like `compare`). Stable.
let Array.sortWith f a = Array.ofList (List.sortWith f (Array.toList a))

// ---------------------------------------------------------------- Option, Result (more)

/// `[x]` for `Some x`, `[]` for `None`.
let Option.toList o =
  match o with
  | Some x -> [ x ]
  | None -> []

/// The option itself if it is `Some`, otherwise `other`.
let Option.orElse other o =
  match o with
  | Some _ -> o
  | None -> other

/// Calls `f` on the value of `Some`; does nothing for `None`.
let Option.iter f o =
  match o with
  | Some x -> f x
  | None -> ()

/// `Ok x` for `Some x`, `Error err` for `None`.
let Option.toResult err o =
  match o with
  | Some x -> Ok x
  | None -> Error err

/// Applies `f` to the error of `Error`; an `Ok` passes through.
let Result.mapError f r =
  match r with
  | Ok x -> Ok x
  | Error e -> Error (f e)

/// The value of `Ok`, or `d` for an `Error`.
let Result.defaultValue d r =
  match r with
  | Ok x -> x
  | Error _ -> d

/// Whether the result is `Ok`.
let Result.isOk r =
  match r with
  | Ok _ -> true
  | Error _ -> false

/// Whether the result is `Error`.
let Result.isError r = not (Result.isOk r)

/// `Some x` for `Ok x`, `None` for an `Error`.
let Result.toOption r =
  match r with
  | Ok x -> Some x
  | Error _ -> None

// ---------------------------------------------------------------- String

/// Whether the string has no bytes.
let String.isEmpty (s: string) = String.length s = 0
/// Whether `sub` occurs in `s`.
let String.contains (sub: string) (s: string) = String.indexOfFrom s sub 0 >= 0

/// The byte index of the first `sub` in `s`, or `None`.
let String.indexOf (sub: string) (s: string) =
  let i = String.indexOfFrom s sub 0
  if i < 0 then None else Some i

/// Whether `s` begins with `p`.
let String.startsWith (p: string) (s: string) =
  String.length p <= String.length s && String.sub s 0 (String.length p) = p

/// Whether `s` ends with `p`.
let String.endsWith (p: string) (s: string) =
  String.length p <= String.length s && String.sub s (String.length s - String.length p) (String.length p) = p

/// The pieces of `s` between occurrences of `sep`: `String.split ", " "a, b" = ["a"; "b"]`.
let String.split (sep: string) (s: string) =
  let rec go acc start =
    let i = String.indexOfFrom s sep start
    if i < 0 then List.rev (String.sub s start (String.length s - start) :: acc)
    else go (String.sub s start (i - start) :: acc) (i + String.length sep)
  if String.length sep = 0 then [ s ] else go [] 0

/// The strings with `sep` between them.
let String.join (sep: string) (xs: list<string>) =
  match xs with
  | [] -> ""
  | x :: rest -> List.fold (fun acc s -> acc + sep + s) x rest

/// The strings joined with nothing between them.
let String.concat (xs: list<string>) = String.join "" xs

/// `s` repeated `n` times.
let String.repeat n (s: string) =
  let mutable r = ""
  for _ in 1 .. n do
    r <- r + s
  r

/// The integer written in `s` (optional sign, decimal digits), or `None`.
let String.parseInt (s: string) : option<int> =
  let n = String.length s
  if n = 0 then None
  else
    let first = String.byte s 0
    let neg = first = u8 45
    let start = if neg || first = u8 43 then 1 else 0
    if start = n then None
    else
      let mutable acc = 0
      let mutable ok = true
      for i in start .. n - 1 do
        let b = int (String.byte s i)
        if b < 48 || b > 57 then ok <- false else acc <- acc * 10 + (b - 48)
      if ok then Some (if neg then -acc else acc) else None

/// The floating-point number written in `s`, or `None`.
let String.parseFloat (s: string) : option<f64> = if String.isFloat s then Some (String.toFloat s) else None

type string with
  /// Whether `sub` occurs in the string.
  member s.Contains(sub: string) = String.contains sub s
  /// Whether the string begins with `p`.
  member s.StartsWith(p: string) = String.startsWith p s
  /// Whether the string ends with `p`.
  member s.EndsWith(p: string) = String.endsWith p s
  /// The byte index of the first `sub`, or `None`.
  member s.IndexOf(sub: string) = String.indexOf sub s
  /// The pieces between occurrences of `sep`.
  member s.Split(sep: string) = String.split sep s
  /// The `len` bytes starting at byte `start`. Panics if out of range.
  member s.Substring(start: int, len: int) = String.sub s start len
  /// The string without leading and trailing spaces, tabs and line breaks.
  member s.Trim() = String.trim s
  /// The string with ASCII letters in upper case.
  member s.ToUpper() = String.toUpper s
  /// The string with ASCII letters in lower case.
  member s.ToLower() = String.toLower s
  /// The string with every `old` replaced by `by`.
  member s.Replace(old: string, by: string) = String.replace s old by

// ---------------------------------------------------------------- Console

/// Writes the string to standard output, without a newline.
let Console.print (s: string) = print s
/// Writes the string and a newline to standard output.
let Console.println (s: string) = println s
/// Writes the string and a newline to standard error.
let Console.eprintln (s: string) = eprintln s

/// The next line of standard input without its newline, or `None` at the end.
let Console.readLine () =
  let line = Console.readLineRaw ()
  if Console.eof () then None else Some line
