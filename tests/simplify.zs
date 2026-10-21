// Simplification after inlining: matches on values whose case is known, matches on matches,
// and lambdas applied where they're bound. Each result must be what the program means; the
// allocation counts show the options and closures that are no longer built.
type Shape =
  | Circle of r: f64
  | Square of side: f64
  | Named of string * f64

let area s =
  match s with
  | Circle r -> 3.0 * r * r
  | Square a -> a * a
  | Named (_, a) -> a

let parse (s: string) =
  match s with
  | "c" -> Some (Circle 1.0)
  | "s" -> Some (Square 2.0)
  | "" -> None
  | other -> Some (Named (other, 5.0))

let describe (s: string) =
  // a match on an inlined match: each path builds an option this match takes apart
  match parse s with
  | Some (Named (n, a)) -> $"{n} of area {a}"
  | Some shape -> $"area {area shape}"
  | None -> "nothing"

let firstWord (s: string) =
  match String.split " " s with
  | w :: _ when w <> "" -> Some w
  | _ -> None

let shout (s: string) = Option.map (fun (w: string) -> w.ToUpper() + "!") (firstWord s)

let classify n =
  let sign = if n < 0 then Error "negative" else Ok n
  // a match on a let-bound value: known on each path
  match sign |> Result.map (fun x -> x * 2) with
  | Ok 0 -> "zero"
  | Ok v when v > 100 -> $"big {v}"
  | Ok v -> $"small {v}"
  | Error e -> e

let rec sumLengths (xs: list<string>) acc =
  // an inlined test: no bool built, the branches take the list apart
  if List.isEmpty xs then acc else sumLengths (List.tail xs) (acc + String.length (List.head xs))

let tally (words: list<string>) =
  let mutable count = 0
  let mutable letters = 0
  for w in words do
    // several paths reach the same case: one copy of its body, jumped to
    match (if w = "" then None else if w = "-" then None else Some w) with
    | Some word ->
      count <- count + 1
      letters <- letters + String.length word
    | None -> ()
  (count, letters)

let pairUp (a: option<string>) (b: option<string>) =
  let both = match a with
    | Some x -> (match b with
      | Some y -> Some (x + y)
      | None -> Some x)
    | None -> b
  match both with
  | Some s -> s
  | None -> "-"

let main () =
  let before = Runtime.allocations ()
  let shapes = [ "c"; "s"; ""; "hexagon" ] |> List.map describe
  println $"{shapes}"
  println $"{shout "hello world"} {shout ""} {shout " x"}"
  println $"{classify 0} {classify 7} {classify 80} {classify -3}"
  println $"{sumLengths [ "ab"; "cde"; "" ] 0} {tally [ "a"; ""; "bc"; "-"; "def" ]}"
  println $"{pairUp (Some "a") (Some "b")} {pairUp (Some "a") None} {pairUp None (Some "b")} {pairUp None None}"
  // a lambda bound by let and only called: no closure
  let k = 10
  let addK = fun x -> x + k
  let mark = Runtime.allocations ()
  let total = addK 1 + addK 2
  let closures = Runtime.allocations () - mark
  println $"{total} {closures}"
  // a known option through a let: the Some isn't built
  let o = Some (String.length "four")
  let n =
    match o with
    | Some v -> v + 1
    | None -> 0
  println $"{n} {before >= 0}"
  0
