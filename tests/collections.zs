// Phase 2: lists, arrays, mutation, loops, strings, floats, options
type Shape<'a> =
  | Circle of 'a
  | Square of 'a

let area s =
  match s with
  | Circle r -> 3.0 * r * r
  | Square w -> w * w

let rec describe xs =
  match xs with
  | [] -> "end"
  | [ x ] -> $"last {x}"
  | x :: rest -> $"{x}, " + describe rest

let main () =
  let xs = List.init 5 (fun i -> i * i)
  println (describe xs)
  println $"length {List.length xs}, rev head {List.head (List.rev xs)}, append {List.length (xs @ xs)}"
  println $"find {List.tryFind (fun x -> x > 5) xs |> Option.defaultValue (-1)} {Option.isNone (List.tryFind (fun x -> x > 99) xs)}"
  let mutable arr = Array.init 5 (fun i -> i + 1)
  arr.[0] <- 10
  println $"array sum {Array.sum arr}, len {Array.length arr}, back to list {List.sum (Array.toList arr)}"
  let words = [| "a"; "bb"; "ccc" |]
  let mutable total = 0
  for i in 0 .. Array.length words - 1 do
    total <- total + String.length words.[i]
  println $"chars {total}"
  let mutable n = 0
  while n < 10 do
    n <- n + 3
  println $"while {n}"
  for i in 10 .. -5 .. 0 do
    print $"{i} "
  println ""
  let shapes = [ Circle 1.0; Square 2.0; Circle 0.5 ]
  println $"areas {List.fold (fun acc s -> acc + area s) 0.0 shapes}"
  let half = float 7 / 2.0
  println $"floats {half} {int (half * 2.0)} {f32 1.5} {1.0 / 3.0}"
  let bytes = u8 250
  let less = "abc" < "abd"
  println $"u8 {Int.wrappingAdd bytes (u8 10)} i8 {i8 -128} cmp {less}"
  let mutable names = Array.ofList [ "x"; "y" ]
  names.[1] <- names.[0] + "z"
  println $"strings {names.[0]} {names.[1]}"
  0
