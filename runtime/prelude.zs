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
