// Z# prelude: compiled before every program.
// List functions are tail-recursive (loops after codegen) so long lists don't exhaust the stack.
// ponytail: map/filter build reversed then List.rev; tail recursion modulo cons would save the pass

// Operator traits. Primitive types have built-in impls; user types implement them with `impl`.
trait Add<'a> =
  abstract add : 'a -> 'a -> 'a
  abstract zero : 'a

trait Num<'a> =
  abstract sub : 'a -> 'a -> 'a
  abstract mul : 'a -> 'a -> 'a
  abstract div : 'a -> 'a -> 'a
  abstract rem : 'a -> 'a -> 'a
  abstract neg : 'a -> 'a

trait Eq<'a> =
  abstract equal : 'a -> 'a -> bool

trait Ord<'a> =
  abstract compare : 'a -> 'a -> int

trait Show<'a> =
  abstract show : 'a -> string

trait Hash<'a> =
  abstract hash : 'a -> int

// What `Shape.kind` matches in a derive.
type ShapeKind =
  | RecordKind
  | UnionKind

// Structural equality, ordering, hashing and printing for every record and union. Each is
// derived the first time a type needs it; an explicit impl, [<NoEquality>] or
// [<NoComparison>] takes precedence.
derive Eq =
  let equal (a: 'self) (b: 'self) =
    match Shape.pair a b with
    | Same c ->
      let mutable same = true
      for f in c.fields do
        if same then same <- f.left = f.right
      same
    | Different _ -> false

derive Ord =
  let compare (a: 'self) (b: 'self) =
    match Shape.pair a b with
    | Same c ->
      let mutable r = 0
      for f in c.fields do
        if r = 0 then r <- compare f.left f.right
      r
    | Different (i, j) -> compare i j

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

type option<'a> =
  | None
  | Some of 'a

type result<'a, 'e> =
  | Ok of 'a
  | Error of 'e

let id x = x
let fst (a, _) = a
let snd (_, b) = b
let max a b = if a > b then a else b
let min a b = if a < b then a else b

let List.rev xs =
  let rec go acc xs =
    match xs with
    | [] -> acc
    | x :: rest -> go (x :: acc) rest
  go [] xs

let List.length xs =
  let rec go n xs =
    match xs with
    | [] -> n
    | _ :: rest -> go (n + 1) rest
  go 0 xs

let List.isEmpty xs =
  match xs with
  | [] -> true
  | _ -> false

let List.head xs =
  match xs with
  | x :: _ -> x
  | [] -> panic "List.head: empty list"

let List.tail xs =
  match xs with
  | _ :: rest -> rest
  | [] -> panic "List.tail: empty list"

let List.map f xs =
  let rec go acc xs =
    match xs with
    | [] -> List.rev acc
    | x :: rest -> go (f x :: acc) rest
  go [] xs

let List.filter f xs =
  let rec go acc xs =
    match xs with
    | [] -> List.rev acc
    | x :: rest -> if f x then go (x :: acc) rest else go acc rest
  go [] xs

let List.fold f state xs =
  let rec go acc xs =
    match xs with
    | [] -> acc
    | x :: rest -> go (f acc x) rest
  go state xs

let List.iter f xs =
  let rec go xs =
    match xs with
    | [] -> ()
    | x :: rest ->
      f x
      go rest
  go xs

let List.append xs ys =
  let rec go acc xs =
    match xs with
    | [] -> acc
    | x :: rest -> go (x :: acc) rest
  go ys (List.rev xs)

let List.exists f xs =
  let rec go xs =
    match xs with
    | [] -> false
    | x :: rest -> if f x then true else go rest
  go xs

let List.forall f xs =
  let rec go xs =
    match xs with
    | [] -> true
    | x :: rest -> if f x then go rest else false
  go xs

let List.contains x xs = List.exists (fun y -> y = x) xs

let List.tryFind f xs =
  let rec go xs =
    match xs with
    | [] -> None
    | x :: rest -> if f x then Some x else go rest
  go xs

let List.sum xs = List.fold (fun acc x -> acc + x) Add.zero xs

let List.init n f =
  let rec go acc i =
    if i < 0 then acc else go (f i :: acc) (i - 1)
  go [] (n - 1)

let Option.map f o =
  match o with
  | Some x -> Some (f x)
  | None -> None

let Option.bind f o =
  match o with
  | Some x -> f x
  | None -> None

let Option.defaultValue d o =
  match o with
  | Some x -> x
  | None -> d

let Option.isSome o =
  match o with
  | Some _ -> true
  | None -> false

let Option.isNone o = not (Option.isSome o)

let Option.get o =
  match o with
  | Some x -> x
  | None -> panic "Option.get: None"

let Result.map f r =
  match r with
  | Ok x -> Ok (f x)
  | Error e -> Error e

let Result.bind f r =
  match r with
  | Ok x -> f x
  | Error e -> Error e

let Array.init n f =
  if n <= 0 then [||]
  else
    let a = Array.create n (f 0)
    for i in 1 .. n - 1 do
      a.[i] <- f i
    a

let Array.map f a = Array.init (Array.length a) (fun i -> f a.[i])

let Array.iter f a =
  for i in 0 .. Array.length a - 1 do
    f a.[i]

let Array.fold f state a =
  let mutable acc = state
  for i in 0 .. Array.length a - 1 do
    acc <- f acc a.[i]
  acc

let Array.sum a = Array.fold (fun acc x -> acc + x) Add.zero a

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

let Array.toList a =
  let rec go acc i =
    if i < 0 then acc else go (a.[i] :: acc) (i - 1)
  go [] (Array.length a - 1)

// members on built-in types
type string with
  member s.Length = String.length s

type array<'a> with
  member a.Length = Array.length a

type list<'a> with
  member xs.Length = List.length xs
  member xs.Head = List.head xs
  member xs.Tail = List.tail xs
  member xs.IsEmpty = List.isEmpty xs

type option<'a> with
  member o.IsSome = Option.isSome o
  member o.IsNone = Option.isNone o

impl Show<list<'a>> =
  let show xs =
    let rec go acc first xs =
      match xs with
      | [] -> acc
      | x :: rest -> go (acc + (if first then "" else "; ") + show x) false rest
    "[" + go "" true xs + "]"

// ---------------------------------------------------------------- List (more)

let List.mapi f xs =
  let rec go acc i xs =
    match xs with
    | [] -> List.rev acc
    | x :: rest -> go (f i x :: acc) (i + 1) rest
  go [] 0 xs

let List.indexed xs = List.mapi (fun i x -> (i, x)) xs

let List.choose f xs =
  let rec go acc xs =
    match xs with
    | [] -> List.rev acc
    | x :: rest ->
      match f x with
      | Some y -> go (y :: acc) rest
      | None -> go acc rest
  go [] xs

let List.collect f xs = List.fold (fun acc x -> List.append acc (f x)) [] xs

let List.zip xs ys =
  let rec go acc xs ys =
    match (xs, ys) with
    | (x :: xr, y :: yr) -> go ((x, y) :: acc) xr yr
    | _ -> List.rev acc
  go [] xs ys

let List.unzip xs = (List.map fst xs, List.map snd xs)

let List.tryHead xs =
  match xs with
  | x :: _ -> Some x
  | [] -> None

let List.last xs =
  let rec go x xs =
    match xs with
    | [] -> x
    | y :: rest -> go y rest
  match xs with
  | x :: rest -> go x rest
  | [] -> panic "List.last: empty list"

let List.item n xs =
  let rec go i xs =
    match xs with
    | x :: rest -> if i = 0 then x else go (i - 1) rest
    | [] -> panic "List.item: index out of range"
  go n xs

let List.take n xs =
  let rec go acc n xs =
    if n <= 0 then List.rev acc
    else
      match xs with
      | x :: rest -> go (x :: acc) (n - 1) rest
      | [] -> List.rev acc
  go [] n xs

let rec List.skip n xs =
  if n <= 0 then xs
  else
    match xs with
    | _ :: rest -> List.skip (n - 1) rest
    | [] -> []

let List.reduce f xs =
  match xs with
  | x :: rest -> List.fold f x rest
  | [] -> panic "List.reduce: empty list"

let List.partition f xs =
  let rec go yes no xs =
    match xs with
    | [] -> (List.rev yes, List.rev no)
    | x :: rest -> if f x then go (x :: yes) no rest else go yes (x :: no) rest
  go [] [] xs

let List.max xs = List.reduce (fun a b -> if b > a then b else a) xs
let List.min xs = List.reduce (fun a b -> if b < a then b else a) xs
let List.sumBy f xs = List.fold (fun acc x -> acc + f x) Add.zero xs

// ponytail: quadratic; fine for short lists, use a hash set when one exists
let List.distinct xs =
  List.rev (List.fold (fun acc x -> if List.contains x acc then acc else x :: acc) [] xs)

// stable merge sort
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

let List.sort xs = List.sortWith compare xs
let List.sortBy f xs = List.sortWith (fun a b -> compare (f a) (f b)) xs

// ---------------------------------------------------------------- Array (more)

let Array.copy a = Array.init (Array.length a) (fun i -> a.[i])
let Array.mapi f a = Array.init (Array.length a) (fun i -> f i a.[i])
let Array.exists f a = List.exists f (Array.toList a)
let Array.contains x a = Array.exists (fun y -> y = x) a
let Array.filter f a = Array.ofList (List.filter f (Array.toList a))
let Array.append a b = Array.ofList (List.append (Array.toList a) (Array.toList b))
let Array.sub a start len = Array.init len (fun i -> a.[start + i])
let Array.rev a = Array.init (Array.length a) (fun i -> a.[Array.length a - 1 - i])
let Array.sort a = Array.ofList (List.sort (Array.toList a))
let Array.sortWith f a = Array.ofList (List.sortWith f (Array.toList a))

// ---------------------------------------------------------------- Option, Result (more)

let Option.toList o =
  match o with
  | Some x -> [ x ]
  | None -> []

let Option.orElse other o =
  match o with
  | Some _ -> o
  | None -> other

let Option.iter f o =
  match o with
  | Some x -> f x
  | None -> ()

let Option.toResult err o =
  match o with
  | Some x -> Ok x
  | None -> Error err

let Result.mapError f r =
  match r with
  | Ok x -> Ok x
  | Error e -> Error (f e)

let Result.defaultValue d r =
  match r with
  | Ok x -> x
  | Error _ -> d

let Result.isOk r =
  match r with
  | Ok _ -> true
  | Error _ -> false

let Result.isError r = not (Result.isOk r)

let Result.toOption r =
  match r with
  | Ok x -> Some x
  | Error _ -> None

// ---------------------------------------------------------------- String

let String.isEmpty (s: string) = String.length s = 0
let String.contains (sub: string) (s: string) = String.indexOfFrom s sub 0 >= 0

let String.indexOf (sub: string) (s: string) =
  let i = String.indexOfFrom s sub 0
  if i < 0 then None else Some i

let String.startsWith (p: string) (s: string) =
  String.length p <= String.length s && String.sub s 0 (String.length p) = p

let String.endsWith (p: string) (s: string) =
  String.length p <= String.length s && String.sub s (String.length s - String.length p) (String.length p) = p

let String.split (sep: string) (s: string) =
  let rec go acc start =
    let i = String.indexOfFrom s sep start
    if i < 0 then List.rev (String.sub s start (String.length s - start) :: acc)
    else go (String.sub s start (i - start) :: acc) (i + String.length sep)
  if String.length sep = 0 then [ s ] else go [] 0

let String.join (sep: string) (xs: list<string>) =
  match xs with
  | [] -> ""
  | x :: rest -> List.fold (fun acc s -> acc + sep + s) x rest

let String.concat (xs: list<string>) = String.join "" xs

let String.repeat n (s: string) =
  let mutable r = ""
  for _ in 1 .. n do
    r <- r + s
  r

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

let String.parseFloat (s: string) : option<f64> = if String.isFloat s then Some (String.toFloat s) else None

type string with
  member s.Contains(sub: string) = String.contains sub s
  member s.StartsWith(p: string) = String.startsWith p s
  member s.EndsWith(p: string) = String.endsWith p s
  member s.IndexOf(sub: string) = String.indexOf sub s
  member s.Split(sep: string) = String.split sep s
  member s.Substring(start: int, len: int) = String.sub s start len
  member s.Trim() = String.trim s
  member s.ToUpper() = String.toUpper s
  member s.ToLower() = String.toLower s
  member s.Replace(old: string, by: string) = String.replace s old by

// ---------------------------------------------------------------- Console

let Console.print (s: string) = print s
let Console.println (s: string) = println s
let Console.eprintln (s: string) = eprintln s

let Console.readLine () =
  let line = Console.readLineRaw ()
  if Console.eof () then None else Some line
