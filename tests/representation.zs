// How unions are represented (DESIGN §5.1), checked through what programs can see: values,
// equality, printing, allocation counts, and (under ZS_LEAKCHECK and valgrind) freeing.
//   - option<string> and other unions of option's shape whose field is a pointer: the field
//     itself, so Some allocates nothing;
//   - cases without fields of boxed unions: static cells, told apart by their address;
//   - a boxed union with one case with fields has no tag in its cells;
//   - unions without heap data are plain values, and an enum is a byte.
type Color =
  | Red
  | Green
  | Blue

type Name =
  | NoName
  | Name of string

type Token =
  | Eof
  | Newline
  | Word of string

type Expr =
  | Zero
  | Num of int
  | Neg of Expr
  | Add of Expr * Expr

let rec eval e =
  match e with
  | Zero -> 0
  | Num n -> n
  | Neg a -> -(eval a)
  | Add (a, b) -> eval a + eval b

let describe t =
  match t with
  | Eof -> "eof"
  | Newline -> "newline"
  | Word w -> $"word {w}"

let lookup (k: string) (pairs: list<string * string>) =
  let rec go xs =
    match xs with
    | [] -> None
    | (a, b) :: rest -> if a = k then Some b else go rest
  go pairs

let greet n =
  match n with
  | Name s -> $"hello {s}"
  | NoName -> "hello"

let main () =
  // a niche: Some is its field
  let pairs = [ ("a", "1"); ("b", "2") ]
  let before = Runtime.allocations ()
  let found = lookup "b" pairs
  let missing = lookup "z" pairs
  let allocated = Runtime.allocations () - before
  println $"lookup: {found} {missing} allocations {allocated}"
  println $"equal: {found = Some "2"} {missing = None} {found = missing} {compare found missing}"
  // options inside options can't both be the field: the outer one is boxed
  let nested = [ Some (Some "x"); Some None; None ]
  for o in nested do
    match o with
    | Some (Some s) -> println $"some some {s}"
    | Some None -> println "some none"
    | None -> println "none"
  // an empty list is a static cell: Some [] isn't None
  let lists = [ Some [ 1; 2 ]; Some []; None ]
  println $"{lists} {lists |> List.map (fun o -> Option.isSome o)}"
  let f = Some (fun x -> x + 1)
  let arr = Some [| 3; 4 |]
  match (f, arr) with
  | (Some g, Some a) -> println $"closure and array: {g 1} {a.[1]}"
  | _ -> println "?"
  println $"{greet (Name "ada")}, {greet NoName}, {Name "x" = Name "x"}"
  // several cases without fields, one with: no tag in the cells
  let toks = [ Word "let"; Newline; Word "x"; Eof ]
  println (String.join ", " (List.map describe toks))
  println $"{toks} {toks = [ Word "let"; Newline; Word "x"; Eof ]} {hash Eof = hash Eof}"
  // several cases with fields: tagged cells
  let e = Add (Num 3, Neg (Add (Num 1, Zero)))
  println $"eval {eval e}, {e}, {compare (Neg Zero) (Num 1)}"
  // a unique list is mapped in place, whatever its cells look like
  let words = List.init 100 (fun i -> Word $"{i}")
  let before = Runtime.allocations ()
  let marked = words |> List.map (fun w -> match w with
    | Word s -> Word s
    | other -> other)
  let allocated = Runtime.allocations () - before
  println $"mapped {List.length marked} with {allocated} allocations"
  // an enum is a byte
  let colors = Array.init 6 (fun i -> if i % 3 = 0 then Red else if i % 3 = 1 then Green else Blue)
  println $"{Array.toList colors} {colors.[4] = Green} {compare Red Blue} {List.sort [ Blue; Red; Green ]}"
  0
